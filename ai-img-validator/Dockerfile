FROM python:3.11-slim

WORKDIR /app

# Install system dependencies required by Pillow/torch on slim images
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      libjpeg62-turbo-dev \
      zlib1g-dev \
      libpng-dev \
      libtiff5-dev \
      libopenblas-dev \
      libomp-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]


