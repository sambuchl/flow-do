import unittest
from app import create_app, db
from config import TestConfig


class AppTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app(TestConfig)
        self.client = self.app.test_client()

    def test_health(self):
        response = self.client.get('/health')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json, {'status': 'ok', 'service': 'flowdo'})

    def test_boundaries_and_extensions(self):
        self.assertEqual(set(self.app.blueprints), {'main', 'auth', 'api', 'errors'})
        self.assertIn('migrate', self.app.extensions)
        with self.app.app_context():
            self.assertIsNone(db.engine.url.database)
            self.assertEqual(list(db.metadata.tables), [])

    def test_api_and_browser_not_found(self):
        for path in ['/missing', '/api/current-task', '/auth/register']:
            response = self.client.get(path)
            self.assertEqual(response.status_code, 404)
            self.assertEqual(response.json, {'error': 'Not Found'})

    def test_method_not_allowed_preserves_headers(self):
        response = self.client.post('/health')
        self.assertEqual(response.status_code, 405)
        self.assertIn('GET', response.headers['Allow'])

    def test_internal_error_hides_details(self):
        self.app.config['PROPAGATE_EXCEPTIONS'] = False
        @self.app.get('/broken')
        def broken():
            raise RuntimeError('private detail')
        with self.assertLogs(self.app.logger, level='ERROR'):
            response = self.client.get('/broken')
        self.assertEqual(response.status_code, 500)
        self.assertEqual(response.json, {'error': 'Internal Server Error'})

    def test_factories_are_independent(self):
        other = create_app(TestConfig)
        self.app.config['FLOWDO_MARKER'] = True
        self.assertNotIn('FLOWDO_MARKER', other.config)
        with self.app.app_context():
            first_engine = db.engine
        with other.app_context():
            self.assertIsNot(first_engine, db.engine)
