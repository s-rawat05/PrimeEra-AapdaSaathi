# AapdaSaathi API + worker. Build context is the repository root (needs fixtures/ for demo mode):
#   docker build -f worker/Dockerfile -t aapdasaathi-api .
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 FIXTURES_DIR=/srv/fixtures
WORKDIR /srv/worker

COPY worker/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY worker/app ./app
COPY fixtures /srv/fixtures
COPY supabase /srv/supabase
COPY scripts/apply_migrations.py /srv/scripts/apply_migrations.py

RUN useradd --create-home --uid 10001 app && mkdir -p /srv/worker/data && chown -R app /srv/worker/data
USER app

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/v1/health').status==200 else 1)"
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers"]
