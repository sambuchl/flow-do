from app.main import bp


@bp.get('/health')
def health():
    return {'status': 'ok', 'service': 'flowdo'}
