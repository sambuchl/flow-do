import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parents[1] / '.env')


class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY') or None
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL') or 'sqlite:///flowdo.db'
    if SQLALCHEMY_DATABASE_URI.startswith(('postgres://', 'postgresql://')):
        SQLALCHEMY_DATABASE_URI = SQLALCHEMY_DATABASE_URI.replace(
            SQLALCHEMY_DATABASE_URI.split('://')[0] + '://',
            'postgresql+psycopg://', 1)
    SQLALCHEMY_TRACK_MODIFICATIONS = False


class TestConfig(Config):
    TESTING = True
    SECRET_KEY = 'test-only'
    SQLALCHEMY_DATABASE_URI = 'sqlite://'
