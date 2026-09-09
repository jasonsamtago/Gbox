package xhttp

import (
	"errors"
	"io"
	"net"
	"sync"
	"time"

	"github.com/metacubex/mihomo/common/httputils"
)

type Conn struct {
	writer  io.WriteCloser
	reader  io.ReadCloser
	onClose func()
	httputils.NetAddr

	stateMu            sync.Mutex
	deadline           *time.Timer
	deadlineGeneration uint64
	closed             bool
	closeDone          chan struct{}
	closeErr           error
}

func (c *Conn) Write(b []byte) (int, error) {
	return c.writer.Write(b)
}

func (c *Conn) Read(b []byte) (int, error) {
	return c.reader.Read(b)
}

func (c *Conn) Close() error {
	return c.close(0, false)
}

func (c *Conn) close(deadlineGeneration uint64, fromDeadline bool) error {
	c.stateMu.Lock()
	if fromDeadline && deadlineGeneration != c.deadlineGeneration {
		c.stateMu.Unlock()
		return nil
	}
	if c.closed {
		done := c.closeDone
		c.stateMu.Unlock()
		<-done
		return c.closeErr
	}
	c.closed = true
	c.deadlineGeneration++
	if c.deadline != nil {
		c.deadline.Stop()
		c.deadline = nil
	}
	c.closeDone = make(chan struct{})
	done := c.closeDone
	c.stateMu.Unlock()

	err := c.writer.Close()
	err2 := c.reader.Close()
	if c.onClose != nil {
		c.onClose()
	}
	err = errors.Join(err, err2)

	c.stateMu.Lock()
	c.closeErr = err
	close(done)
	c.stateMu.Unlock()
	return err
}

func (c *Conn) SetReadDeadline(t time.Time) error  { return c.SetDeadline(t) }
func (c *Conn) SetWriteDeadline(t time.Time) error { return c.SetDeadline(t) }

func (c *Conn) SetDeadline(t time.Time) error {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()
	if c.closed {
		return net.ErrClosed
	}
	c.deadlineGeneration++
	deadlineGeneration := c.deadlineGeneration
	if c.deadline != nil {
		c.deadline.Stop()
		c.deadline = nil
	}
	if t.IsZero() {
		return nil
	}
	c.deadline = time.AfterFunc(time.Until(t), func() {
		_ = c.close(deadlineGeneration, true)
	})
	return nil
}
