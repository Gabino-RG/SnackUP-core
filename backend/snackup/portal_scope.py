"""Staff entry points with isolated browser cookies and explicit role checks.

The original /api endpoints remain available to existing clients. A staff URL
is a routing boundary, never a replacement for account/endpoint authorization.
"""
from urllib.parse import urlsplit
from starlette.responses import JSONResponse
from .errors import ApiError

PORTALS = {'cocina': 'business', 'administracion': 'admin'}
SCOPE_KEY = 'snackup.portal'


class PortalScopeMiddleware:
    """Rewrite before guards, admission, routing and websocket authentication."""
    def __init__(self, app, settings):
        self.app, self.settings = app, settings

    async def __call__(self, scope, receive, send):
        if scope['type'] in {'http', 'websocket'}:
            hosts = [value.decode('latin-1') for key, value in scope.get('headers', []) if key.lower() == b'host']
            audience = None
            try:
                if len(hosts) != 1 or hosts[0].endswith(':') or any(character.isspace() for character in hosts[0]):
                    raise ValueError('Ambiguous Host')
                host = urlsplit('//' + hosts[0])
                if (not host.hostname or host.username is not None or host.password is not None or host.path or host.query or host.fragment
                        or host.hostname.endswith('.')):
                    raise ValueError('Invalid Host')
                port = host.port  # Validate malformed or out-of-range ports.
                configured = [(None, self.settings.public_origin)] + [
                    (portal, self.settings.staff_origin_for_role(role)) for portal, role in PORTALS.items()
                    if self.settings.staff_origin_for_role(role)]
                for portal, origin in configured:
                    endpoint = urlsplit(origin)
                    if host.hostname.lower() == endpoint.hostname.lower():
                        default_port = 443 if endpoint.scheme == 'https' else 80
                        if (default_port if port is None else port) != (endpoint.port or default_port):
                            raise ValueError('Unexpected public port')
                        audience = portal
                        break
            except ValueError:
                await self.deny(scope, receive, send)
                return
            scope = dict(scope)
            scope[SCOPE_KEY] = audience
            for portal in PORTALS:
                prefix = '/' + portal
                path = scope.get('path', '')
                if (path.startswith(prefix + '/api/') or path == prefix + '/api'
                        or path.startswith(prefix + '/socket.io/') or path == prefix + '/socket.io'):
                    # When separate origins exist, never expose a second shared-
                    # origin entrance and never reinterpret the other staff host.
                    configured = self.settings.staff_origin_for_role(PORTALS[portal])
                    if (audience is not None and audience != portal) or (configured and audience != portal):
                        await self.deny(scope, receive, send)
                        return
                    scope[SCOPE_KEY] = portal
                    scope['snackup.portal_prefix'] = prefix
                    scope['path'] = path[len(prefix):]
                    scope['raw_path'] = scope['path'].encode('utf-8')
                    break
        await self.app(scope, receive, send)

    @staticmethod
    async def deny(scope, receive, send):
        if scope['type'] == 'websocket':
            await send({'type': 'websocket.close', 'code': 1008})
        else:
            await JSONResponse({'error': {'code': 'PORTAL_ORIGIN_MISMATCH',
                'message': 'Este acceso no pertenece a este sitio.'}}, status_code=403,
                headers={'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'})(scope, receive, send)


def portal_for(request):
    return request.scope.get(SCOPE_KEY)


def expected_role(request):
    return PORTALS.get(portal_for(request))


def expected_origin(request):
    return request.app.state.settings.origin_for_role(expected_role(request))


def role_matches(request, role):
    return role_matches_portal(portal_for(request), role)


def role_matches_portal(portal, role):
    required = PORTALS.get(portal)
    return required is None or role == required


def require_portal_role(request, role):
    require_role_for_portal(portal_for(request), role)
    require_browser_entry(request.app.state.settings, portal_for(request), request.headers.get('origin'), role)


def require_browser_entry(settings, portal, origin, role):
    # Preserve the original native API, but do not keep issuing browser staff
    # sessions on the students' origin after distinct staff sites are enabled.
    if portal is None and origin == settings.public_origin and settings.staff_origin_for_role(role):
        raise ApiError(403, 'PORTAL_ORIGIN_MISMATCH', 'Utiliza el sitio correspondiente a tu cuenta.')


def require_role_for_portal(portal, role):
    if not role_matches_portal(portal, role):
        label = 'Cocina' if portal == 'cocina' else 'Administración'
        raise ApiError(403, 'PORTAL_ROLE_MISMATCH', 'Esta cuenta no tiene acceso a ' + label + '.')


def refresh_cookie(request=None):
    portal = portal_for(request) if request is not None else None
    if portal in PORTALS:
        # __Host- cookies cannot be shadowed by a parent-domain cookie from
        # another subdomain: the browser requires Secure, Path=/ and no Domain.
        configured = request.app.state.settings.staff_origin_for_role(PORTALS[portal])
        if configured and configured.startswith('https://'):
            return '__Host-snackup_refresh_' + portal, '/'
        prefix = request.scope.get('snackup.portal_prefix', '')
        return 'snackup_refresh_' + portal, prefix + '/api'
    return 'snackup_refresh', '/api'


def session_matches_portal(request, session, db):
    if expected_role(request) is None:
        return True
    from .identity_models import User
    user = db.get(User, session.user_id)
    return user is not None and role_matches(request, user.role)
