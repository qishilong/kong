---
-- Client TLS connection module.
--
-- A set of functions for interacting with TLS connections from the client.
--
-- @module kong.client.tls


local phase_checker = require "kong.pdk.private.phases"
local kong_tls = require "resty.kong.tls"


local check_phase = phase_checker.check
local error = error
local type = type
local ngx = ngx


local PHASES = phase_checker.phases
local REWRITE_AND_LATER = phase_checker.new(PHASES.rewrite,
                                            PHASES.access,
                                            PHASES.response,
                                            PHASES.balancer,
                                            PHASES.log)
local REWRITE_BEFORE_LOG = phase_checker.new(PHASES.rewrite,
                                             PHASES.access,
                                             PHASES.response,
                                             PHASES.balancer)


local function new()
  local _TLS = {}


  ---
  -- Requests the client to present its client-side certificate to initiate mutual
  -- TLS authentication between server and client.
  --
  -- This function *requests*, but does not *require* the client to start
  -- the mTLS process. The TLS handshake can still complete even if the client
  -- doesn't present a client certificate. However, in that case, it becomes a
  -- TLS connection instead of an mTLS connection, as there is no mutual
  -- authentication.
  --
  -- To find out whether the client honored the request, use
  -- `get_full_client_certificate_chain` in later phases.
  --
  -- @function kong.client.tls.request_client_certificate
  -- @phases certificate
  -- @treturn true|nil Returns `true` if request is received, or `nil` if
  -- request fails.
  -- @treturn nil|err Returns `nil` if the handshake is successful, or an error
  -- message if it fails.
  --
  -- @usage
  -- local res, err = kong.client.tls.request_client_certificate()
  -- if not res then
  --   -- do something with err
  -- end
  function _TLS.request_client_certificate()
    check_phase(PHASES.certificate)

    return kong_tls.request_client_certificate()
  end


  ---
  -- Prevents the TLS session for the current connection from being reused
  -- by disabling the session ticket and session ID for the current TLS connection.
  --
  -- @function kong.client.tls.disable_session_reuse
  -- @phases certificate
  -- @treturn true|nil Returns `true` if successful, `nil` if it fails.
  -- @treturn nil|err Returns `nil` if successful, or an error message if it fails.
  --
  -- @usage
  -- local res, err = kong.client.tls.disable_session_reuse()
  -- if not res then
  --   -- do something with err
  -- end
  function _TLS.disable_session_reuse()
    check_phase(PHASES.certificate)

    return kong_tls.disable_session_reuse()
  end


  ---
  -- Sets the CA DN list to the underlying SSL structure, which will be sent in the
  -- Certificate Request Message of downstram TLS handshake.
  --
  -- The downstream client then can use this DN information to filter certificates,
  -- and chooses an appropriate certificate issued by a CA in the list.
  --
  -- The type of `ca_list` paramter is `STACK_OF(X509) *` which can be created by
  -- using the API of `resty.openssl.x509.chain` or `parse_pem_cert()` of `ngx.ssl`
  --
  -- @function kong.client.tls.set_client_ca_list
  -- @phases certificate
  -- @tparam cdata ca_list The ca certificate chain whose dn(s) will be sent
  -- @treturn true|nil Returns `true` if successful, `nil` if it fails.
  -- @treturn nil|err Returns `nil` if successful, or an error message if it fails.
  --
  -- @usage
  -- local x509_lib = require "resty.openssl.x509"
  -- local chain_lib = require "resty.openssl.x509.chain"
  -- local res, err
  -- local chain = chain_lib.new()
  -- -- err check
  -- local x509, err = x509_lib.new(pem_cert, "PEM")
  -- -- err check
  -- res, err = chain:add(x509)
  -- -- err check
  -- -- `chain.ctx` is the raw data of the chain, i.e. `STACK_OF(X509) *`
  -- res, err = kong.client.tls.set_client_ca_list(chain.ctx)
  -- if not res then
  --   -- do something with err
  -- end
  function _TLS.set_client_ca_list(ca_list)
    check_phase(PHASES.certificate)

    return kong_tls.set_client_ca_list(ca_list)
  end


  ---
  -- Returns the PEM encoded downstream client certificate chain with the
  -- client certificate at the top and intermediate certificates
  -- (if any) at the bottom.
  --
  -- @function kong.client.tls.get_full_client_certificate_chain
  -- @phases rewrite, access, balancer, header_filter, body_filter, log
  -- @treturn string|nil Returns a PEM-encoded client certificate if the mTLS
  -- handshake was completed, or `nil` if an error occurred or the client did
  -- not present its certificate.
  -- @treturn nil|err Returns `nil` if successful, or an error message if it fails.
  --
  -- @usage
  -- local cert, err = kong.client.get_full_client_certificate_chain()
  -- if err then
  --   -- do something with err
  -- end
  --
  -- if not cert then
  --   -- client did not complete mTLS
  -- end
  --
  -- -- do something with cert
  function _TLS.get_full_client_certificate_chain()
    check_phase(REWRITE_AND_LATER)

    return kong_tls.get_full_client_certificate_chain()
  end



  ---
  -- Overrides the client's verification result generated by the log serializer.
  --
  -- By default, the `request.tls.client_verify` field inside the log
  -- generated by Kong's log serializer is the same as the
  -- [$ssl_client_verify](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#var_ssl_client_verify)
  -- Nginx variable.
  --
  -- Only `"SUCCESS"`, `"NONE"`, or `"FAILED:<reason>"` are accepted values.
  --
  -- This function does not return anything on success, and throws a Lua error
  -- in case of a failure.
  --
  -- @function kong.client.tls.set_client_verify
  -- @phases rewrite, access, balancer
  --
  -- @usage
  -- kong.client.tls.set_client_verify("FAILED:unknown CA")
  function _TLS.set_client_verify(v)
    check_phase(REWRITE_BEFORE_LOG)

    assert(type(v) == "string")

    if v ~= "SUCCESS" and v ~= "NONE" and v:sub(1, 7) ~= "FAILED:" then
      error("unknown client verify value: " .. tostring(v) ..
            " accepted values are: \"SUCCESS\", \"NONE\"" ..
            " or \"FAILED:<reason>\"", 2)
    end

    ngx.ctx.CLIENT_VERIFY_OVERRIDE = v
  end


  return _TLS
end


return {
  new = new,
}
