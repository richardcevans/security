"""Completion represents learner actions, not pre-existing database objects."""
from contextlib import ExitStack
import importlib
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ENV = {
    'ADMIN_FLASK_SECRET_KEY': 'workflow-test-only', 'ADMIN_DB_DSN': 'unused-test-dsn',
    'ORDER_HISTORY_BUCKET': 'test-bucket', 'ORDER_HISTORY_NAMESPACE': 'test-namespace',
    'ORDER_HISTORY_READ_PAR_URL': 'https://example.invalid/read',
    'ORDER_HISTORY_PREFIX': 'order_history/', 'GENAI_DEFAULTS_FILE': '/nonexistent/workflow-test',
}
with patch.dict(os.environ, ENV):
    application = importlib.import_module('admin_app')


class WorkflowProgressTests(unittest.TestCase):
    def setUp(self):
        self.contexts = ExitStack()
        self.addCleanup(self.contexts.close)
        self.contexts.enter_context(patch.dict(application.app.config, TESTING=True, WTF_CSRF_ENABLED=False))
        self.contexts.enter_context(patch.dict(application._logins, {}, clear=True))
        self.contexts.enter_context(patch.object(application, 'verify_admin', return_value='ADMIN'))
        self.ready = self.contexts.enter_context(patch.object(application, '_database_completed_actions', return_value=set(application.ACTIONS)))
        self.sql = self.contexts.enter_context(patch.object(application, '_run_action', return_value={'exit_code': 0, 'output': 'Executed successfully.'}))
        self.contexts.enter_context(patch.object(application, '_run_data_grant_sql', return_value={'exit_code': 0, 'output': 'Grant applied.'}))
        self.client = application.app.test_client()
        self.assertEqual(self.client.post('/api/login', json={'password': 'test-only'}).status_code, 200)

    def progress(self):
        with self.client.session_transaction() as session:
            return application._logins[session['_user_id']]['completed_actions']

    def run_action(self, key):
        result = self.client.post('/api/actions/' + key)
        self.assertEqual(result.status_code, 200)
        return result.get_json()

    def test_existing_database_objects_do_not_precomplete_any_page(self):
        for page in application.PAGES:
            with self.subTest(page=page['key']):
                response = self.client.get(page['path'])
                self.assertEqual(response.status_code, 200)
                self.assertIn(b"data-completed-actions='[]'", response.data)
        self.ready.assert_not_called()

    def test_success_survives_other_actions_and_page_loads(self):
        self.run_action('create_roles')
        result = self.run_action('create_data_grants')
        self.assertEqual(set(result['completed_actions']), {'create_roles', 'create_data_grants'})
        self.client.get('/deep-sec-basics')
        self.assertEqual(self.progress(), {'create_roles', 'create_data_grants'})

    def test_failure_does_not_import_database_progress(self):
        self.sql.return_value = {'exit_code': 1, 'output': 'SQL failed.'}
        response = self.client.post('/api/actions/grant_employee_access')
        self.assertEqual(response.status_code, 422)
        self.assertEqual(response.get_json()['completed_actions'], [])
        self.ready.assert_not_called()

    def basics_complete(self):
        pages, _ = application._navigation_state(self.progress())
        return next(p for p in pages if p['key'] == 'deep_sec_basics')['completed']

    def test_review_requires_successful_action_and_correct_quiz(self):
        step = next(s for s in application.STEPS if s['key'] == 'review')
        answer = step['quiz']['correct_answer']
        path = '/api/steps/review/quiz'
        self.assertEqual(self.client.post(path, json={'answer': answer}).status_code, 409)
        for action in ['create_roles', 'create_data_grants', 'create_end_users', 'grant_employee_access', 'review_light']:
            self.run_action(action)
        self.assertFalse(self.basics_complete())
        response = self.client.post(path, json={'answer': 'wrong'})
        self.assertFalse(response.get_json()['correct'])
        self.assertFalse(self.basics_complete())
        response = self.client.post(path, json={'answer': answer})
        self.assertTrue(response.get_json()['correct'])
        self.assertTrue(self.basics_complete())
        self.assertIn('quiz:review', self.progress())
        self.assertIn('quiz:review', self.client.get('/deep-sec-basics').get_data(as_text=True))

    def test_invalid_quiz_requests_cannot_record_completion(self):
        for path, payload, status in [('/api/steps/missing/quiz', {}, 404), ('/api/steps/review/quiz', [], 400), ('/api/steps/review/quiz', {}, 400)]:
            self.assertEqual(self.client.post(path, json=payload).status_code, status)
        self.assertEqual(self.progress(), set())

    def test_reset_clears_previous_progress_and_records_its_own_success(self):
        self.run_action('create_roles')
        result = self.run_action('reset_lab')
        self.assertEqual(result['completed_actions'], ['reset_lab'])
        with self.client.session_transaction() as session:
            outputs = application._logins[session['_user_id']]['action_outputs']
        self.assertEqual(set(outputs), {'reset_lab'})

    def test_restore_does_not_credit_unseen_review_or_quiz(self):
        for key in ['restore_db_setup', 'restore_deep_sec_setup']:
            with self.subTest(action=key):
                self.progress().add('quiz:review')
                result = self.run_action(key)
                expected = set(application.ACTIONS[key]['restored_actions']) | {key}
                self.assertEqual(set(result['completed_actions']), expected)
                self.assertNotIn('review_light', expected)
                self.assertNotIn('review_db_setup', expected)
                self.assertFalse(any(item.startswith('quiz:') for item in expected))
                self.assertFalse(self.basics_complete())

    def test_database_prerequisites_allow_wizard_without_precompleting_other_steps(self):
        self.contexts.enter_context(patch.object(application, '_build_configured_grant', return_value='-- test grant'))
        response = self.client.post('/api/actions/customize_employee_grant/apply', json={})
        self.assertEqual(response.status_code, 200)
        self.ready.assert_called_once()
        self.assertEqual(response.get_json()['completed_actions'], ['customize_employee_grant'])

    def test_download_records_completion_only_after_archive_is_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'example.zip'
            path.write_bytes(b'example archive')
            with application.app.test_request_context():
                with patch.object(application.current_user, 'get_id', return_value=next(iter(application._logins))):
                    response = application._download_response(path, 'example.zip', 'sql_scripts')
                    self.assertIn('download_lab_files', response.headers['X-Completed-Actions'])
                    response.close()
        with patch.object(application, 'build_sql_scripts_zip', side_effect=RuntimeError('failed')):
            self.progress().clear()
            with self.assertRaises(RuntimeError):
                self.client.get('/api/download/sql-scripts')
        self.assertEqual(self.progress(), set())

    def test_alternative_actions_and_best_practice_navigation_use_same_groups(self):
        pages, _ = application._navigation_state(set(application.ACTIONS) | {'quiz:'+s['key'] for s in application.STEPS if s['quiz']})
        self.assertTrue(next(p for p in pages if p['key'] == 'best_practices')['completed'])
        self.assertFalse(next(p for p in pages if p['key'] == 'admin')['completed'])
        manager = next(s for s in application.STEPS if s['key'] == 'grant_manager_role')
        self.assertEqual(manager['completion_groups'], [['enable_manager', 'disable_manager'], ['quiz:grant_manager_role']])

    def test_new_login_starts_a_fresh_learner_workflow(self):
        self.run_action('grant_employee_access')
        self.client.post('/api/logout')
        self.client.post('/api/login', json={'password': 'test-only'})
        self.assertEqual(self.progress(), set())


if __name__ == '__main__':
    unittest.main()
