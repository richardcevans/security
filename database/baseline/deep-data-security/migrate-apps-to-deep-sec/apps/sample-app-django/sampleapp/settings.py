import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = 'django-insecure-^ol@+4iwt&$ymm2^(&j%kwn$(#$qr)0ki)5b4(l#9d_fnsb*8k'

DEBUG = True

ALLOWED_HOSTS = ['*']

INSTALLED_APPS = [
    'django.contrib.sessions',
    'django.contrib.staticfiles',
    'employees',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'sampleapp.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
            ],
        },
    },
]

WSGI_APPLICATION = 'sampleapp.wsgi.application'

# Use file-based sessions (no database needed)
SESSION_ENGINE = 'django.contrib.sessions.backends.file'

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'

# Oracle connection settings — configurable via environment variables
_host = os.environ.get('ORACLE_HOST', 'localhost')
_port = os.environ.get('ORACLE_PORT', '2484')
_pdb  = os.environ.get('PDB_NAME',    'pdb1')
ORACLE_DSN = os.environ.get(
    'ORACLE_DSN',
    f'(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST={_host})(PORT={_port}))'
    f'(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME={_pdb}))'
    f')'
)
