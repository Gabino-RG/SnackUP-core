import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile


def module(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


prepare = module('prepare')
configure = module('configure')


class StagingTests(unittest.TestCase):
    def test_package_has_exact_versions_integrity_and_no_private_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'pilot'
            archive = prepare.prepare(root)
            versions = json.loads((root / 'versions.json').read_text(encoding='utf-8'))
            self.assertEqual(versions['panels'], prepare.PANELS)
            self.assertEqual(versions['backend'], prepare.BACKEND)
            for line in (root / 'SHA256SUMS').read_text(encoding='utf-8').splitlines():
                digest, relative = line.split('  ', 1)
                self.assertEqual(hashlib.sha256((root / relative).read_bytes()).hexdigest(), digest, relative)
            with zipfile.ZipFile(archive) as bundle:
                self.assertFalse(any(Path(name).name == '.env' for name in bundle.namelist()))
                self.assertIn('backend/compose.unified.yaml', bundle.namelist())
                template = bundle.read('backend/.env.example').decode('utf-8')
                self.assertIn('SNACKUP_PANELS_CONTEXT=' + prepare.REMOTE + '#' + prepare.PANELS, template)
                for key in configure.SECRETS:
                    self.assertIn(key + '=\n', template)
                self.assertIn('SNACKUP_ADMIN_EMAIL_DOMAINS=\n', template)
            before = archive.read_bytes()
            with self.assertRaises(ValueError):
                prepare.prepare(root)
            self.assertEqual(archive.read_bytes(), before)

    def test_initialization_is_private_unique_and_refuses_to_rotate_existing_secrets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.env.example').write_text('\n'.join(k + '=' for k in configure.REQUIRED), encoding='utf-8')
            configure.initialize(root)
            before = (root / '.env').read_bytes()
            values = dict(line.split('=', 1) for line in before.decode().splitlines())
            self.assertEqual(len({values[k] for k in configure.SECRETS}), 3)
            self.assertTrue(all(len(values[k]) == 64 for k in configure.SECRETS))
            with self.assertRaises(FileExistsError):
                configure.initialize(root)
            self.assertEqual((root / '.env').read_bytes(), before)
            errors = configure.check(root)
            self.assertIn('Falta SNACKUP_DOMAIN', errors)
            self.assertTrue(all(value not in '\n'.join(errors) for value in (values[k] for k in configure.SECRETS)))

    def test_check_accepts_complete_config_and_rejects_sample_hosts_and_floating_refs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            values = {key: 'configured' for key in configure.REQUIRED}
            values.update({key: str(index) * 64 for index, key in enumerate(configure.SECRETS, 1)})
            values.update(SNACKUP_DOMAIN='piloto.universidad.mx', TLS_ACME_EMAIL='operador@universidad.mx',
                          SNACKUP_PANELS_CONTEXT=prepare.REMOTE + '#' + prepare.PANELS,
                          SNACKUP_USERS_CONTEXT=prepare.REMOTE + '#' + prepare.USERS)
            def save():
                (root / '.env').write_text('\n'.join(k + '=' + v for k, v in values.items()), encoding='utf-8')
            save()
            self.assertEqual(configure.check(root), [])
            values['SNACKUP_DOMAIN'] = 'snackup.example.edu'
            values['SNACKUP_PANELS_CONTEXT'] = prepare.REMOTE + '#main'
            save()
            self.assertEqual(len(configure.check(root)), 2)


if __name__ == '__main__':
    unittest.main()
