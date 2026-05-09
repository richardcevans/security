from django.urls import path
from . import views

urlpatterns = [
    path('', views.index, name='index'),
    path('login', views.login_view, name='login'),
    path('logout', views.logout_view, name='logout'),
    path('employees', views.employee_list, name='employee_list'),
    path('api/employees', views.api_employee_list, name='api_employee_list'),
    path('api/employees/<int:employee_id>', views.api_employee_detail, name='api_employee_detail'),
]
