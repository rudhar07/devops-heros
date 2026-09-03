# Python Hello World - single-stage image
FROM python:3.11-slim

# Send Python logs straight to the container output without buffering
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install dependencies in their own layer so it is cached until requirements.txt changes
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code last because it changes most often
COPY app.py .

# Flask listens on 5000 inside the container
EXPOSE 5000

CMD ["python", "app.py"]
