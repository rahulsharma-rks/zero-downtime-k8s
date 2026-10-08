FROM python:3.12-alpine

ARG APP_VERSION=dev

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV APP_VERSION=${APP_VERSION}

RUN apk update && \
    apk upgrade zlib && \
    rm -rf /var/cache/apk/*

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

RUN addgroup -S appgroup && \
    adduser -S -D -H -s /sbin/nologin -G appgroup appuser

USER appuser

EXPOSE 8080

CMD ["python", "app.py"]
