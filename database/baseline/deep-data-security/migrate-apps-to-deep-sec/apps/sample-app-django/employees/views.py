import ssl

import oracledb
from django.conf import settings
from django.http import JsonResponse
from django.shortcuts import render, redirect


def _get_connection(username, password):
    return oracledb.connect(
        user=username,
        password=password,
        dsn=settings.ORACLE_DSN,
        ssl_context=ssl._create_unverified_context(),
    )


def _fetch_employees(conn, employee_id=None):
    sql = (
        "SELECT employee_id, first_name, last_name, job_code, department_id, "
        "ssn, phone_number, salary, user_name, manager_id "
        "FROM hr.employees"
    )
    params = {}
    if employee_id is not None:
        sql += " WHERE employee_id = :id"
        params["id"] = employee_id
    sql += " ORDER BY employee_id"

    with conn.cursor() as cur:
        cur.execute(sql, params)
        columns = [col[0].lower() for col in cur.description]
        return [dict(zip(columns, row)) for row in cur.fetchall()]


def index(request):
    if not request.session.get("db_user"):
        return redirect("login")
    return redirect("employee_list")


def login_view(request):
    if request.method == "POST":
        username = request.POST.get("username", "")
        password = request.POST.get("password", "")
        try:
            conn = _get_connection(username, password)
            conn.close()
            request.session["db_user"] = username
            request.session["db_pass"] = password
            return redirect("employee_list")
        except Exception as e:
            return render(request, "login.html", {"error": f"Login failed: {e}"})
    return render(request, "login.html")


def logout_view(request):
    request.session.flush()
    return redirect("login")


def employee_list(request):
    user = request.session.get("db_user")
    pwd = request.session.get("db_pass")
    if not user:
        return redirect("login")
    try:
        conn = _get_connection(user, pwd)
        employees = _fetch_employees(conn)
        conn.close()
        return render(request, "employees.html", {
            "employees": employees,
            "current_user": user,
        })
    except Exception as e:
        return render(request, "employees.html", {"error": f"Database error: {e}"})


def api_employee_list(request):
    user = request.session.get("db_user")
    pwd = request.session.get("db_pass")
    if not user:
        return JsonResponse({"error": "Not authenticated"}, status=401)
    try:
        conn = _get_connection(user, pwd)
        employees = _fetch_employees(conn)
        conn.close()
        return JsonResponse(employees, safe=False)
    except Exception as e:
        return JsonResponse({"error": str(e)}, status=500)


def api_employee_detail(request, employee_id):
    user = request.session.get("db_user")
    pwd = request.session.get("db_pass")
    if not user:
        return JsonResponse({"error": "Not authenticated"}, status=401)
    try:
        conn = _get_connection(user, pwd)
        employees = _fetch_employees(conn, employee_id)
        conn.close()
        if employees:
            return JsonResponse(employees[0])
        return JsonResponse({"error": "Not found"}, status=404)
    except Exception as e:
        return JsonResponse({"error": str(e)}, status=500)
