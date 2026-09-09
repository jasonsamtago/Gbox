package xhttp

import (
	"errors"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type testReadCloser struct {
	closes atomic.Int64
	err    error
}

func (*testReadCloser) Read([]byte) (int, error) { return 0, io.EOF }
func (c *testReadCloser) Close() error {
	c.closes.Add(1)
	return c.err
}

type testWriteCloser struct {
	closes atomic.Int64
	err    error
}

func (*testWriteCloser) Write(p []byte) (int, error) { return len(p), nil }
func (c *testWriteCloser) Close() error {
	c.closes.Add(1)
	return c.err
}

func TestConnCloseRunsCleanupOnceAndJoinsErrors(t *testing.T) {
	writerErr := errors.New("writer close")
	readerErr := errors.New("reader close")
	reader := &testReadCloser{err: readerErr}
	writer := &testWriteCloser{err: writerErr}
	var callbacks atomic.Int64
	conn := &Conn{
		reader:  reader,
		writer:  writer,
		onClose: func() { callbacks.Add(1) },
	}

	const callers = 16
	errs := make(chan error, callers)
	var wg sync.WaitGroup
	for i := 0; i < callers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			errs <- conn.Close()
		}()
	}
	wg.Wait()
	close(errs)

	for err := range errs {
		if !errors.Is(err, writerErr) || !errors.Is(err, readerErr) {
			t.Fatalf("Close() error = %v, want both underlying errors", err)
		}
	}
	if got := reader.closes.Load(); got != 1 {
		t.Fatalf("reader Close calls = %d, want 1", got)
	}
	if got := writer.closes.Load(); got != 1 {
		t.Fatalf("writer Close calls = %d, want 1", got)
	}
	if got := callbacks.Load(); got != 1 {
		t.Fatalf("onClose calls = %d, want 1", got)
	}
	if err := conn.SetDeadline(time.Now().Add(time.Hour)); !errors.Is(err, net.ErrClosed) {
		t.Fatalf("SetDeadline() after Close error = %v, want net.ErrClosed", err)
	}
}

func TestConnCloseCancelsDeadline(t *testing.T) {
	reader := &testReadCloser{}
	writer := &testWriteCloser{}
	conn := &Conn{reader: reader, writer: writer}

	if err := conn.SetDeadline(time.Now().Add(20 * time.Millisecond)); err != nil {
		t.Fatal(err)
	}
	if err := conn.Close(); err != nil {
		t.Fatal(err)
	}
	time.Sleep(60 * time.Millisecond)

	if got := reader.closes.Load(); got != 1 {
		t.Fatalf("reader Close calls = %d, want 1", got)
	}
	if got := writer.closes.Load(); got != 1 {
		t.Fatalf("writer Close calls = %d, want 1", got)
	}
}

func TestConnClearedAndReplacedDeadlinesDoNotCloseEarly(t *testing.T) {
	for _, tc := range []struct {
		name   string
		update func(*Conn) error
	}{
		{name: "cleared", update: func(c *Conn) error { return c.SetDeadline(time.Time{}) }},
		{name: "replaced", update: func(c *Conn) error { return c.SetDeadline(time.Now().Add(time.Hour)) }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			reader := &testReadCloser{}
			writer := &testWriteCloser{}
			conn := &Conn{reader: reader, writer: writer}
			if err := conn.SetDeadline(time.Now().Add(20 * time.Millisecond)); err != nil {
				t.Fatal(err)
			}
			if err := tc.update(conn); err != nil {
				t.Fatal(err)
			}
			time.Sleep(60 * time.Millisecond)
			if got := reader.closes.Load(); got != 0 {
				t.Fatalf("reader Close calls = %d, want 0", got)
			}
			if got := writer.closes.Load(); got != 0 {
				t.Fatalf("writer Close calls = %d, want 0", got)
			}
			if err := conn.Close(); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestConnObsoleteDeadlineCallbackCannotCloseReplacement(t *testing.T) {
	reader := &testReadCloser{}
	writer := &testWriteCloser{}
	conn := &Conn{reader: reader, writer: writer}
	if err := conn.SetDeadline(time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	conn.stateMu.Lock()
	obsoleteGeneration := conn.deadlineGeneration
	conn.stateMu.Unlock()
	if err := conn.SetDeadline(time.Now().Add(2 * time.Hour)); err != nil {
		t.Fatal(err)
	}

	if err := conn.close(obsoleteGeneration, true); err != nil {
		t.Fatalf("obsolete deadline callback returned %v", err)
	}
	if got := reader.closes.Load(); got != 0 {
		t.Fatalf("reader Close calls = %d, want 0", got)
	}
	if got := writer.closes.Load(); got != 0 {
		t.Fatalf("writer Close calls = %d, want 0", got)
	}
	if err := conn.SetDeadline(time.Now().Add(3 * time.Hour)); err != nil {
		t.Fatalf("connection was closed by obsolete callback: %v", err)
	}
	if err := conn.Close(); err != nil {
		t.Fatal(err)
	}
}

func TestConnOnCloseRunsOutsideStateMutex(t *testing.T) {
	reader := &testReadCloser{}
	writer := &testWriteCloser{}
	callbackDone := make(chan error, 1)
	conn := &Conn{reader: reader, writer: writer}
	conn.onClose = func() {
		callbackDone <- conn.SetDeadline(time.Now().Add(time.Hour))
	}

	closeDone := make(chan error, 1)
	go func() { closeDone <- conn.Close() }()
	select {
	case err := <-callbackDone:
		if !errors.Is(err, net.ErrClosed) {
			t.Fatalf("SetDeadline() from onClose error = %v, want net.ErrClosed", err)
		}
	case <-time.After(time.Second):
		t.Fatal("onClose blocked on connection state mutex")
	}
	select {
	case err := <-closeDone:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("Close did not return")
	}
}

func TestConnDeadlineExpiryClosesOnce(t *testing.T) {
	readerErr := errors.New("reader close")
	writerErr := errors.New("writer close")
	reader := &testReadCloser{err: readerErr}
	writer := &testWriteCloser{err: writerErr}
	closed := make(chan struct{})
	conn := &Conn{
		reader:  reader,
		writer:  writer,
		onClose: func() { close(closed) },
	}

	if err := conn.SetDeadline(time.Now()); err != nil {
		t.Fatal(err)
	}
	select {
	case <-closed:
	case <-time.After(time.Second):
		t.Fatal("deadline did not close connection")
	}

	err := conn.Close()
	if !errors.Is(err, writerErr) || !errors.Is(err, readerErr) {
		t.Fatalf("Close() after deadline error = %v, want both underlying errors", err)
	}
	if got := reader.closes.Load(); got != 1 {
		t.Fatalf("reader Close calls = %d, want 1", got)
	}
	if got := writer.closes.Load(); got != 1 {
		t.Fatalf("writer Close calls = %d, want 1", got)
	}
}

func TestConnConcurrentDeadlineCalls(t *testing.T) {
	reader := &testReadCloser{}
	writer := &testWriteCloser{}
	conn := &Conn{reader: reader, writer: writer}
	start := make(chan struct{})
	var wg sync.WaitGroup
	for worker := 0; worker < 8; worker++ {
		worker := worker
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			for i := 0; i < 1000; i++ {
				deadline := time.Now().Add(time.Hour)
				if (worker+i)%3 == 0 {
					deadline = time.Time{}
				}
				if worker%2 == 0 {
					_ = conn.SetReadDeadline(deadline)
				} else {
					_ = conn.SetWriteDeadline(deadline)
				}
			}
		}()
	}
	close(start)
	wg.Wait()
	if err := conn.SetDeadline(time.Time{}); err != nil {
		t.Fatal(err)
	}
	if err := conn.Close(); err != nil {
		t.Fatal(err)
	}
}
