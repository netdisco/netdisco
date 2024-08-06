class Status:
    def __init__(self, log, status=''):
        self.status = status
        self.log = log or ''

    def is_ok(self):
        return True if self.status == 'done' else False

    def not_ok(self):
        return not self.is_ok()

    def level(self):
        return (
            4
            if self.status == 'error'
            else 3
            if self.status == 'done'
            else 2
            if self.status == 'defer'
            else 1
            if self.status == 'info'
            else 0
        )

    @classmethod
    def done(cls, *args):
        return cls(args, status='done')

    @classmethod
    def info(cls, *args):
        return cls(args, status='info')

    @classmethod
    def defer(cls, *args):
        return cls(args, status='defer')

    @classmethod
    def error(cls, *args):
        return cls(args, status='error')
