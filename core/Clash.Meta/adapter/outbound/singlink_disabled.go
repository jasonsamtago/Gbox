//go:build !singlink

package outbound

import "errors"

// NewSingLink is disabled in ordinary public builds. The explicit offline
// compiler overlay replaces this file; a bare singlink tag is not sufficient.
func NewSingLink(SingLinkOption) (ProxyAdapter, error) {
	return nil, errors.New("SingLink requires the explicit private SDK development build")
}
