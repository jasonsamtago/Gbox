package outbound

// SingLinkOption is public configuration only. Private SDK imports exist solely
// in the explicit developer-build overlay, outside the default Go source graph.
type SingLinkOption struct {
	BasicOption
	Name           string `proxy:"name"`
	Server         string `proxy:"server"`
	Port           int    `proxy:"port"`
	Token          string `proxy:"token" json:"-"`
	SNI            string `proxy:"sni,omitempty"`
	UDP            bool   `proxy:"udp,omitempty"`
	SkipCertVerify bool   `proxy:"skip-cert-verify,omitempty"`
	Transport      string `proxy:"transport,omitempty"`
	MaxPending     int    `proxy:"max-pending,omitempty"`
	MaxStreams     int    `proxy:"max-streams,omitempty"`
	ReceiveWindow  int    `proxy:"receive-window,omitempty"`
	SetupTimeout   int    `proxy:"setup-timeout,omitempty"`
	OpenTimeout    int    `proxy:"open-timeout,omitempty"`
	WriteTimeout   int    `proxy:"write-timeout,omitempty"`
}
