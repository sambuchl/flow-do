"""Reserved for token-authenticated native API; never reuse browser sessions."""
from flask import Blueprint
bp = Blueprint('api', __name__)
