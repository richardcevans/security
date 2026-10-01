"""Browser regressions using real Flask routes and mocked external services.

Run from admin-app with Playwright and Chromium installed:
    PYTHONPATH=. python tests/browser_workflow.py
No OCI, SQL*Plus, or database calls are made.
"""
from contextlib import ExitStack
import io
import json
import re
from urllib.parse import urlsplit
from unittest.mock import patch

from playwright.sync_api import sync_playwright, expect
from test_workflow_progress import application

BLUE = 'rgb(0, 95, 184)'
RED = 'rgb(199, 70, 52)'


def main():
    with ExitStack() as stack:
        stack.enter_context(patch.dict(application.app.config, TESTING=True, WTF_CSRF_ENABLED=False))
        stack.enter_context(patch.dict(application._logins, {}, clear=True))
        stack.enter_context(patch.object(application, 'verify_admin', return_value='ADMIN'))
        stack.enter_context(patch.object(application, '_database_completed_actions', return_value=set(application.ACTIONS)))
        sql = stack.enter_context(patch.object(application, '_run_action', return_value={'exit_code': 0, 'output': 'SQL action succeeded.'}))
        stack.enter_context(patch.object(application, '_run_data_grant_sql', return_value={'exit_code': 0, 'output': 'Grant applied.'}))
        stack.enter_context(patch.object(application, 'validation_comparison', return_value={'available': False, 'message': 'No database in browser tests.'}))
        stack.enter_context(patch.object(application.urllib.request, 'urlopen', side_effect=lambda *a, **k: io.BytesIO(b'{"objects": [{"name": "order_history/metadata/v1.metadata.json"}]}')))
        client = application.app.test_client()
        assert client.post('/api/login', json={'password': 'browser-test-only'}, base_url='http://preview.invalid:7778').status_code == 200
        with client.session_transaction(base_url='http://preview.invalid:7778') as session:
            login_id = session['_user_id']
        def reset_progress():
            application._logins[login_id]['completed_actions'] = set()
            application._logins[login_id]['action_outputs'] = {}
        errors = []
        def serve(route):
            req = route.request
            parsed = urlsplit(req.url)
            assert parsed.hostname == 'preview.invalid', req.url
            if parsed.path.startswith('/api/download/'):
                with application.app.test_request_context():
                    with patch.object(application.current_user, 'get_id', return_value=login_id):
                        completed = application._record_completed_action(application.ACTIONS['download_lab_files'])
                route.fulfill(status=200, headers={'Content-Type':'application/zip','X-Completed-Actions':json.dumps(completed)}, body=b'PK-browser-test')
                return
            response = client.open(parsed.path, method=req.method, data=req.post_data_buffer, headers={'Content-Type':req.headers.get('content-type','')}, base_url='http://preview.invalid:7778')
            route.fulfill(status=response.status_code, headers=dict(response.headers), body=response.data)
        with sync_playwright() as p:
            browser = p.chromium.launch()
            context = browser.new_context(viewport={'width':1280, 'height':900}, accept_downloads=True)
            context.add_cookies([{'name':name,'value':'1','domain':'preview.invalid','path':'/'} for name in ('hol_tour_seen','hol_deebee_greeted')])
            context.route('**/*',serve)
            page = context.new_page()
            page.on('pageerror',lambda error: errors.append(str(error)))
            page.on('dialog',lambda dialog: dialog.accept())
            total = 0
            for lesson_page in application.PAGES:
                reset_progress()
                page.goto('http://preview.invalid:7778'+lesson_page['path'],wait_until='networkidle')
                expect(page.locator('.step-item.is-completed')).to_have_count(0)
                for step_key in lesson_page['step_keys']:
                    step = next(s for s in application.STEPS if s['key']==step_key)
                    badge = page.locator(f'[data-action-step="{step_key}"]')
                    badge.locator('button').click()
                    expect(badge.locator('.step-number')).to_have_css('background-color', RED)
                    panel = page.locator(f'[data-action-panel="{step_key}"]')
                    if step['quiz']:
                        panel.locator(f'input[value="{step["quiz"]["correct_answer"]}"]').check()
                        panel.locator('.check-review-quiz').click()
                        expect(panel.locator('.review-quiz-feedback')).to_contain_text("Complete this step's action")
                        expect(badge).not_to_have_class(re.compile(r'\bis-completed\b'))
                    action = application.ACTIONS[step['action_keys'][0]]
                    if action['type']=='download':
                        with page.expect_download():
                            panel.locator('.download-button').first.click()
                    elif action['type']=='wizard':
                        panel.locator('.run-grant-apply').click()
                    else:
                        panel.locator('.run-action').first.click()
                    if step['quiz']:
                        expect(panel.locator('.action-status').first).to_contain_text('Completed' if action['type']!='wizard' else 'Applied')
                        assert 'is-completed' not in (badge.get_attribute('class') or '')
                        wrong = next(o['key'] for o in step['quiz']['options'] if o['key']!=step['quiz']['correct_answer'])
                        panel.locator(f'input[value="{wrong}"]').check()
                        panel.locator('.check-review-quiz').click()
                        expect(panel.locator('.review-quiz-feedback')).to_contain_text('Not quite')
                        expect(badge.locator('.step-number')).to_have_css('background-color',RED)
                        panel.locator(f'input[value="{step["quiz"]["correct_answer"]}"]').check()
                        panel.locator('.check-review-quiz').click()
                        expect(panel.locator('.review-quiz-feedback')).to_have_class('review-quiz-feedback correct')
                    expect(badge.locator('.step-number')).to_have_css('background-color',BLUE)
                    page.reload(wait_until='networkidle')
                    expect(page.locator(f'[data-action-step="{step_key}"] .step-number')).to_have_css('background-color',BLUE)
                    total += 1
                if lesson_page['ordered']:
                    expect(page.locator(f'.header-link[data-page-key="{lesson_page["key"]}"] .page-check')).to_be_visible()
            print(f'Workflow passed: all {total} steps, all {len(application.PAGES)} pages, action + quiz gating, downloads, reset/restore, navigation, and reload persistence.')

            reset_progress()
            page.goto('http://preview.invalid:7778/deep-sec-basics',wait_until='networkidle')
            page.locator('[data-select-action="grant_employee_access"]').click()
            sql.return_value={'exit_code':1,'output':'Simulated SQL failure'}
            page.locator('[data-action="grant_employee_access"]').click()
            expect(page.locator('#action-grant_employee_access .action-status')).to_have_text('Action did not complete')
            expect(page.locator('[data-action-step="grant_employee_access"] .step-number')).to_have_css('background-color',RED)
            expect(page.locator('.step-item.is-completed')).to_have_count(0)
            sql.return_value={'exit_code':0,'output':'SQL action succeeded.'}
            page.locator('[data-action="grant_employee_access"]').click()
            expect(page.locator('[data-action-step="grant_employee_access"] .step-number')).to_have_css('background-color',BLUE)
            page.screenshot(path='/tmp/deep-sec-workflow-colors.png',full_page=True)

            for viewport in [{'width':1280,'height':900},{'width':390,'height':844},{'width':844,'height':390}]:
                page.set_viewport_size(viewport)
                page.goto('http://preview.invalid:7778/deep-sec-basics',wait_until='networkidle')
                for close_method in ['outside','escape','skip','done']:
                    page.locator('#tour-replay').click()
                    expect(page.locator('.tour-tooltip')).to_have_count(1)
                    expect(page.locator('.tour-backdrop')).to_have_count(1)
                    page.evaluate('window.scrollTo(0, document.body.scrollHeight)')
                    page.wait_for_function('''() => { const r=document.querySelector('.tour-tooltip').getBoundingClientRect(); return r.top >= 0 && r.bottom <= innerHeight && r.left >= 0 && r.right <= innerWidth; }''')
                    page.keyboard.press('Tab')
                    assert page.evaluate("document.querySelector('.tour-tooltip').contains(document.activeElement)")
                    if close_method=='outside':
                        page.mouse.click(viewport['width']-2,viewport['height']-2)
                    elif close_method=='escape':
                        page.keyboard.press('Escape')
                    elif close_method=='skip':
                        page.locator('.tour-skip').click()
                    else:
                        while page.locator('.tour-tooltip').count():
                            page.locator('.tour-next').click()
                    expect(page.locator('.tour-tooltip, .tour-backdrop')).to_have_count(0)
                    page.evaluate('window.scrollTo(0, 0)')
                # Starting twice must leave exactly one tour and one dimming layer.
                page.evaluate('startTour(); startTour();')
                expect(page.locator('.tour-tooltip')).to_have_count(1)
                expect(page.locator('.tour-backdrop')).to_have_count(1)
                page.keyboard.press('Escape')
                expect(page.locator('.tour-tooltip, .tour-backdrop')).to_have_count(0)
            print('Tour passed: scroll, desktop/mobile/landscape bounds, outside click, Escape, Skip, Done, focus containment, and repeated launches.')

            context.clear_cookies()
            page.set_viewport_size({'width':1280,'height':900})
            page.goto('http://preview.invalid:7778/console',wait_until='networkidle')
            expect(page.locator('.deebee-popup')).to_be_visible()
            expect(page.locator('.tour-backdrop')).to_have_count(0)
            page.mouse.click(2,2)
            expect(page.locator('.deebee-popup, .deebee-popup-backdrop, .tour-tooltip, .tour-backdrop')).to_have_count(0)
            # A second task on the event loop would expose an already-queued auto-tour.
            page.wait_for_timeout(500)
            expect(page.locator('.tour-backdrop')).to_have_count(0)
            context.clear_cookies()
            page.reload(wait_until='networkidle')
            expect(page.locator('.deebee-popup')).to_be_visible()
            page.locator('.deebee-popup-dismiss').click()
            expect(page.locator('.tour-tooltip')).to_be_visible()
            expect(page.locator('.deebee-popup, .deebee-popup-backdrop')).to_have_count(0)
            page.keyboard.press('Escape')
            expect(page.locator('.tour-tooltip, .tour-backdrop')).to_have_count(0)
            assert not errors,errors
            browser.close()
            print('Greeting/tour transition passed; no JavaScript errors or stranded overlays.')


if __name__=='__main__':
    main()
