# syntax=docker/dockerfile:1

FROM node:alpine as build

WORKDIR /app

# wget embedding model weight from alpine (does not exist from slim-buster)
RUN wget "https://chroma-onnx-models.s3.amazonaws.com/all-MiniLM-L6-v2/onnx.tar.gz" -O - | \
    tar -xzf - -C /app



COPY . .



FROM python:3.11-slim-bookworm as base

ENV RAG_EMBEDDING_MODEL="all-MiniLM-L6-v2"
# device type for whisper tts and embbeding models - "cpu" (default), "cuda" (nvidia gpu and CUDA required) or "mps" (apple silicon) - choosing this right can lead to better performance
ENV RAG_EMBEDDING_MODEL_DEVICE_TYPE="cpu"
ENV RAG_EMBEDDING_MODEL_DIR="/app/data/cache/embedding/models"
ENV SENTENCE_TRANSFORMERS_HOME $RAG_EMBEDDING_MODEL_DIR

ENV OPENAI_API_BASE_URL "https://api.adamchatbot.chat/v1"
ENV OPENAI_API_KEY "sk-OQyJrrKA7y7g4vdUCbDcAf768bB7468d8153BfD93b37Cf42"


######## Preloaded models ########

WORKDIR /app/backend

# install python dependencies
COPY ./backend/requirements.txt ./requirements.txt

RUN apt-get update && apt-get install ffmpeg libsm6 libxext6  -y

RUN pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --no-cache-dir
RUN pip3 install -r requirements.txt --no-cache-dir

# Install pandoc and netcat
# RUN python -c "import pypandoc; pypandoc.download_pandoc()"
RUN apt-get update \
    && apt-get install -y pandoc netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# preload embedding model
RUN python -c "import os; from chromadb.utils import embedding_functions; sentence_transformer_ef = embedding_functions.SentenceTransformerEmbeddingFunction(model_name=os.environ['RAG_EMBEDDING_MODEL'], device=os.environ['RAG_EMBEDDING_MODEL_DEVICE_TYPE'])"
# preload tts model
RUN python -c "import os; from faster_whisper import WhisperModel; WhisperModel(os.environ['WHISPER_MODEL'], device='auto', compute_type='int8', download_root=os.environ['WHISPER_MODEL_DIR'])"

# copy embedding weight from build
RUN mkdir -p /root/.cache/chroma/onnx_models/all-MiniLM-L6-v2
COPY --from=build /app/onnx /root/.cache/chroma/onnx_models/all-MiniLM-L6-v2/onnx

# copy built frontend files
COPY --from=build /app/build /app/build
COPY --from=build /app/CHANGELOG.md /app/CHANGELOG.md
COPY --from=build /app/package.json /app/package.json

# copy backend files
COPY ./backend .

CMD [ "bash", "start.sh"]
