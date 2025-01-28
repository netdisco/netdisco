"""
netdisco.util.database
~~~~~~~~~~~~~~~~~~~~~~

Access to Netdisco database using SQLAlchemy and psycopg (v3).
"""

import os
from sqlalchemy import create_engine, URL

db_connect_url = URL.create(
    drivername='postgresql+psycopg',
    username=os.environ.get('PGUSER', None),
    password=os.environ.get('PGPASSWORD', None),
    host=os.environ.get('PGHOST', None),
    port=os.environ.get('PORT', None),
    database=os.environ.get('PGDATABASE', None),
)

engine = create_engine(
    db_connect_url, echo=False if os.environ.get('DBIC_TRACE', '0') == '0' else True
)
