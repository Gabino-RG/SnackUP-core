import unittest
from check_panels_server import inspect, origin


class ProbeTests(unittest.TestCase):
    def fixture(self, url):
        headers = {'Content-Type': 'application/json', 'X-Content-Type-Options': 'nosniff',
                   'X-Frame-Options': 'DENY', 'Cache-Control': 'no-cache'}
        body = b'{}'
        if url.endswith('/health/live'):
            body = b'{"status":"ok"}'
        elif url.endswith('/health/ready'):
            body = b'{"status":"ready"}'
        elif url.endswith('.js'):
            headers['Content-Type'] = 'application/javascript'
            body = b'function main() {}'
        elif url.endswith('/paneles/'):
            headers['Content-Type'] = 'text/html'
            body = b'<html><base href="/paneles/"></html>'
        return 200, headers, body

    def test_routes_pass_without_credentials_or_student_routes(self):
        paths = []
        def fetch(url):
            paths.append(url)
            return self.fixture(url)
        self.assertTrue(inspect('https://campus.test', fetch)['passed'])
        self.assertEqual(len(paths), 6)
        self.assertFalse(any('/usuarios' in p for p in paths))

    def test_html_fallback_in_api_fails(self):
        def fetch(url):
            return 200, {'Content-Type': 'text/html'}, b'<html>unexpected</html>'
        self.assertFalse(inspect('https://campus.test', fetch)['passed'])

    def test_network_failure_is_recorded_without_sensitive_detail(self):
        def fetch(url):
            raise RuntimeError('secret must not enter report')
        report = inspect('https://campus.test', fetch)
        self.assertFalse(report['passed'])
        self.assertNotIn('secret', str(report))

    def test_only_https_origin_is_accepted(self):
        self.assertEqual(origin('https://campus.test/'), 'https://campus.test')
        for value in ['http://campus.test', 'https://user:password@campus.test',
                      'https://campus.test/path', 'https://campus.test?token=secret']:
            with self.assertRaises(ValueError):
                origin(value)


if __name__ == '__main__':
    unittest.main()
