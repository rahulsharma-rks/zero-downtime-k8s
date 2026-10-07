import os
from flask import Flask

app = Flask(__name__)

APP_VERSION = os.getenv("APP_VERSION", "dev")

@app.route("/")
def home():
    return f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Zero Downtime Demo</title>
    </head>
    <body>
        <h1>Zero Downtime Kubernetes Demo</h1>
        <p>Application Version: <strong>{APP_VERSION}</strong></p>
        <p>Status: <strong>Running - Zero Downtime Deployment</strong></p>
    </body>
    </html>
    """

@app.route("/health")
def health():
    return "OK", 200

@app.route("/ready")
def ready():
    return "NOT READY", 503

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)

