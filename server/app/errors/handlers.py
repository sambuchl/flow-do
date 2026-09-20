import json

from werkzeug.exceptions import HTTPException
from app import db
from app.errors import bp


@bp.app_errorhandler(HTTPException)
def http_error(error):
    # Keep protocol headers (e.g. Allow on 405), including for future API routes.
    response = error.get_response()
    response.set_data(json.dumps({'error': error.name}))
    response.content_type = 'application/json'
    if error.code == 500:
        db.session.rollback()
    return response
