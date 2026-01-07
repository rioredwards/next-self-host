"""
FastAPI backend exposing NSFW + dog detection via OpenNSFW and ImageNet.

This service is intended to run alongside the Next.js app as `ai-img-validator`.
"""

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from opennsfw_standalone import OpenNSFWInferenceRunner

from io import BytesIO
from PIL import Image
import logging

import torch
from torchvision import models, transforms

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="NSFW + Dog Filter API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tighten in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


runner: OpenNSFWInferenceRunner | None = None
dog_model: torch.nn.Module | None = None
preprocess: transforms.Compose | None = None


def load_nsfw_model() -> None:
    """Load the NSFW model once at startup."""
    global runner
    logger.info("Loading OpenNSFW model...")
    runner = OpenNSFWInferenceRunner.load()
    logger.info("OpenNSFW model loaded.")


def load_dog_model() -> None:
    """Load the ImageNet dog classifier (MobileNetV2) and preprocessing."""
    global dog_model, preprocess

    logger.info("Loading dog detection model (MobileNetV2)...")
    dog_model = models.mobilenet_v2(weights="DEFAULT")
    dog_model.eval()

    preprocess = transforms.Compose(
        [
            transforms.Resize(256),
            transforms.CenterCrop(224),
            transforms.ToTensor(),
            transforms.Normalize(
                mean=[0.485, 0.456, 0.406],
                std=[0.229, 0.224, 0.225],
            ),
        ]
    )

    logger.info("Dog detection model loaded.")


@app.on_event("startup")
async def startup_event() -> None:
    load_nsfw_model()
    load_dog_model()


@app.get("/")
async def root():
    return {
        "status": "ok",
        "service": "NSFW + Dog Filter API",
        "nsfw_model_loaded": runner is not None,
        "dog_model_loaded": dog_model is not None,
    }


def analyze_nsfw(image_bytes: bytes) -> tuple[bool, float]:
    """Run NSFW detection and return (is_nsfw, score)."""
    if runner is None:
        raise RuntimeError("NSFW model not loaded")

    try:
        Image.open(BytesIO(image_bytes)).verify()
    except Exception as e:
        logger.error(f"Invalid image data: {e}")
        raise HTTPException(status_code=400, detail="Invalid image file") from e

    score = runner.infer(image_bytes)
    is_nsfw = bool(score > 0.5)
    return is_nsfw, float(score)


def analyze_dog(image_bytes: bytes, threshold: float = 0.2) -> tuple[bool, float]:
    """Analyze if image contains a dog using ImageNet classes."""
    if dog_model is None or preprocess is None:
        raise RuntimeError("Dog model not loaded")

    try:
        img = Image.open(BytesIO(image_bytes)).convert("RGB")
    except Exception as e:
        logger.error(f"Invalid image data for dog analysis: {e}")
        raise HTTPException(status_code=400, detail="Invalid image file") from e

    input_tensor = preprocess(img).unsqueeze(0)

    with torch.no_grad():
        logits = dog_model(input_tensor)
        probs = torch.softmax(logits, dim=1)[0]

    # ImageNet dog class range ≈ 151–268
    dog_prob = probs[151:269].sum().item()
    return dog_prob > threshold, float(dog_prob)


@app.post("/analyze")
async def analyze_image(file: UploadFile = File(...)):
    """
    Analyze an uploaded image for NSFW content and dog probability.

    Response:
    - filename
    - nsfw_score (0.0–1.0)
    - is_nsfw (bool)
    - dog_probability (0.0–1.0)
    - is_dog (bool)
    """
    if runner is None:
        raise HTTPException(status_code=503, detail="NSFW model not loaded")
    if dog_model is None:
        raise HTTPException(status_code=503, detail="Dog model not loaded")

    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="File must be an image")

    image_bytes = await file.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Empty file")

    try:
        is_nsfw, nsfw_score = analyze_nsfw(image_bytes)
        is_dog, dog_prob = analyze_dog(image_bytes)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error during analysis: {e}")
        raise HTTPException(status_code=500, detail="Error processing image") from e

    return JSONResponse(
        {
            "filename": file.filename,
            "nsfw_score": round(nsfw_score, 4),
            "is_nsfw": bool(is_nsfw),
            "dog_probability": round(dog_prob, 4),
            "is_dog": bool(is_dog),
        }
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)


