"""Serve the complete SnackUP web application on this computer only."""

import argparse
import functools
import http.server
import os
from pathlib import Path
import socket
import sys
import webbrowser


class SnackUpHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "application/javascript",
        ".mjs": "application/javascript",
        ".json": "application/json",
    }

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()

    def list_directory(self, path):
        self.send_error(404, "Not found")
        return None

    def log_message(self, format, *args):
        pass

    def log_error(self, format, *args):
        print("HTTP: " + (format % args), file=sys.stderr, flush=True)


class LocalServer(http.server.ThreadingHTTPServer):
    # On Windows, exclusive binding prevents another process sharing this port.
    # On Unix, disabling address reuse also makes an occupied port fail clearly.
    allow_reuse_address = False

    def server_bind(self):
        if sys.platform == "win32" and hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()


def parse_port(value):
    try:
        port = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("El puerto debe ser un numero entero.") from error
    if not 0 <= port <= 65535:
        raise argparse.ArgumentTypeError("El puerto debe estar entre 0 y 65535.")
    return port


def main():
    parser = argparse.ArgumentParser(description="SnackUP: aplicacion completa para PC")
    parser.add_argument("--port", type=parse_port, default=8790,
                        help="Puerto local fijo (8790); 0 elige uno libre para pruebas.")
    parser.add_argument("--no-browser", action="store_true",
                        help="No abrir el navegador automaticamente.")
    options = parser.parse_args()
    web_root = Path(__file__).resolve().parent / "web"
    if not (web_root / "index.html").is_file():
        print("Falta la carpeta web. Usa 'Extraer todo' en el ZIP antes de iniciar.", flush=True)
        return 1

    handler = functools.partial(SnackUpHandler, directory=str(web_root))
    try:
        server = LocalServer(("127.0.0.1", options.port), handler)
    except OSError as error:
        print(f"No se pudo iniciar SnackUP en el puerto {options.port}: {error}", flush=True)
        print("Si ya abriste SnackUP, usa esa ventana o cierrala antes de reiniciar.", flush=True)
        print("No se abrio el navegador ni se eligio otro puerto.", flush=True)
        return 1

    url = f"http://localhost:{server.server_port}/"
    with server:
        print("\nSNACKUP | APLICACION COMPLETA", flush=True)
        print("Conexion real a Firebase. Requiere Internet y una cuenta de SnackUP.", flush=True)
        print("Los pedidos, resenas y cambios permitidos se guardan en el servicio conectado.", flush=True)
        print("El acceso administrativo depende de los permisos asignados a tu cuenta.", flush=True)
        print(f"\nAbre esta direccion en tu navegador: {url}", flush=True)
        print("Manten esta ventana abierta mientras usas SnackUP.", flush=True)
        print("Para terminar, pulsa Ctrl+C o cierra esta ventana.\n", flush=True)
        if not options.no_browser:
            try:
                if sys.platform == "win32":
                    os.startfile(url)
                else:
                    webbrowser.open(url)
            except (OSError, webbrowser.Error):
                print("Copia la direccion anterior y abrela manualmente.", flush=True)
        try:
            server.serve_forever(poll_interval=0.2)
        except KeyboardInterrupt:
            print("\nSnackUP cerrado.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
