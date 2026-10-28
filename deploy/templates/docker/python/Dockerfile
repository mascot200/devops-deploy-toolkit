# syntax=docker/dockerfile:1
# Python web app (Flask/Django/FastAPI). Copy to your repo root as ./Dockerfile and adjust the lines marked ADJUST.
# Build:  docker build -t my-app:dev .      Run: docker run --rm -p 8080:8080 my-app:dev

FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8080
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
# never run as root inside the container
RUN useradd --create-home --uid 10001 app
USER app
EXPOSE 8080
# ADJUST: your server. requirements.txt must include it (gunicorn for Flask/Django, uvicorn for FastAPI).
#   FastAPI: CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
# The app must serve GET /healthz -> 200.
CMD ["sh", "-c", "gunicorn --bind 0.0.0.0:${PORT} --workers 2 --access-logfile - app:app"]
