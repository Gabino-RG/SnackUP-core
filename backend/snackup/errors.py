class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str = 'No se pudo completar la solicitud.', details=None, *, audit=None):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.details = details
        # Internal metadata only, persisted after the failed transaction rolls
        # back. Never serialized, and never include attempted pickup secrets.
        self.audit = audit

    def payload(self):
        error = {'code': self.code, 'message': self.message}
        if self.details is not None:
            error['details'] = self.details
        return {'error': error}
