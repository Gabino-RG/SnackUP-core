from sqlalchemy import func, select

from snackup import cli
from snackup.auth import password_matches
from snackup.identity_models import AcademicRecord, Career, RefreshSession, User
from snackup.db import Base, Database


def passwords(monkeypatch, value='Another-Test-Password-934!'):
    monkeypatch.setattr(cli, 'getpass', lambda _: value)


def test_bootstrap_never_overwrites_or_creates_a_second_master(app, monkeypatch, capsys):
    passwords(monkeypatch)
    result = cli.main(['create-master', '--email', 'new@staff.example.edu', '--name', 'Responsable'], app.state.settings)
    assert result == 1
    assert 'Ya existe' in capsys.readouterr().err
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(User).where(User.is_master.is_(True))) == 1
        assert not db.scalar(select(User).where(User.email == 'new@staff.example.edu'))


def test_private_bootstrap_creates_only_the_requested_master(app, tmp_path, monkeypatch, capsys):
    passwords(monkeypatch)
    settings = app.state.settings.model_copy(update={'database_url': 'sqlite:///' + (tmp_path / 'empty.db').as_posix()})
    database = Database(settings)
    try:
        Base.metadata.create_all(database.engine)
        assert cli.main(['create-master', '--email', 'new@staff.example.edu', '--name', 'Responsable'], settings) == 0
        assert 'Another-Test' not in capsys.readouterr().out
        with database.sessions() as db:
            users = db.scalars(select(User)).all()
            assert len(users) == 1
            assert users[0].is_master and users[0].email_verified and users[0].role == 'admin'
            assert password_matches('Another-Test-Password-934!', users[0].password_hash)
    finally:
        database.dispose()


def test_private_master_recovery_hashes_password_and_revokes_tokens(app, client, tokens, monkeypatch, capsys):
    passwords(monkeypatch)
    assert cli.main(['reset-master-password', '--email', 'master@staff.example.edu'], app.state.settings) == 0
    output = capsys.readouterr().out
    assert 'Another-Test' not in output
    assert client.get('/api/legacy/v1/users/me', headers=tokens['master']).status_code == 401
    with app.state.db.sessions() as db:
        user = db.get(User, 'master')
        assert password_matches('Another-Test-Password-934!', user.password_hash)
        assert user.auth_version == 2
        assert all(s.revoked_at for s in db.scalars(select(RefreshSession).where(RefreshSession.user_id == 'master')))


def test_roster_dry_run_rolls_back_careers_and_people(app, tmp_path, capsys):
    source = tmp_path / 'authorized.csv'
    source.write_text('email,institutional_id,display_name,kind,career_id,career_name,group_id,group_name,is_active\n'
                      'new@students.example.edu,NEW-1,New Student,student,new-career,Otra carrera,,,true\n', encoding='utf-8')
    args = ['import-roster', str(source), '--source', 'Prueba autorizada']
    assert cli.main([*args, '--dry-run'], app.state.settings) == 0
    assert '"dryRun": true' in capsys.readouterr().out
    with app.state.db.sessions() as db:
        assert db.get(Career, 'new-career') is None
        assert db.scalar(select(AcademicRecord).where(AcademicRecord.institutional_id == 'NEW-1')) is None
    assert cli.main(args, app.state.settings) == 0
    with app.state.db.sessions() as db:
        assert db.get(Career, 'new-career') is not None
        assert db.scalar(select(AcademicRecord).where(AcademicRecord.institutional_id == 'NEW-1')) is not None


def test_bootstrap_requires_configured_domain_and_matching_passwords(app, monkeypatch, capsys):
    passwords(monkeypatch)
    assert cli.main(['create-master', '--email', 'person@unapproved.example', '--name', 'Person'], app.state.settings) == 1
    assert 'SNACKUP_ADMIN_EMAIL_DOMAINS' in capsys.readouterr().err
    values = iter(['Test-Password-12!', 'Different-Password-12!'])
    monkeypatch.setattr(cli, 'getpass', lambda _: next(values))
    assert cli.main(['reset-master-password', '--email', 'master@staff.example.edu'], app.state.settings) == 1
    assert 'no coinciden' in capsys.readouterr().err
