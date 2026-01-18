# --- Stdlib (Librerías Estándar) ---
import json
import os
import base64
import logging
import posixpath as pp # Usamos posixpath para manejar rutas S3

# --- AWS ---
import boto3
from botocore.exceptions import ClientError

# --- Imagen (OpenCV y NumPy) ---
import cv2
import numpy as np

# --- Configuración del Logger ---
log = logging.getLogger()
log.setLevel(logging.INFO)

# --- Clientes de AWS ---
s3 = boto3.client("s3")
ssm = boto3.client("ssm")

# ==============================================================================
# CLASE DE CONFIGURACIÓN
# ==============================================================================
class Config:
    PROCESS_IMAGES_BUCKET = os.getenv("PROCESS_IMAGES_BUCKET")
    DIRECTORIES_MAP_PARAM = os.getenv("DIRECTORIES_MAP") # Nombre del parámetro SSM
    OUTPUT_DIM = int(os.getenv("B1_OUTPUT_DIM", "2400"))
    JPEG_QUALITY = int(os.getenv("B1_JPEG_QUALITY", "95"))

    @staticmethod
    def validate():
        if not Config.PROCESS_IMAGES_BUCKET:
            raise RuntimeError("Error Crítico: Falta la variable de entorno 'PROCESS_IMAGES_BUCKET'.")
        if not Config.DIRECTORIES_MAP_PARAM:
            raise RuntimeError("Error Crítico: Falta la variable de entorno 'DIRECTORIES_MAP'.")

# ==============================================================================
# HELPER PARA LEER SSM (CON CACHÉ)
# ==============================================================================
_ssm_cache = {}

def get_ssm_json(param_name: str) -> dict:
    if param_name in _ssm_cache:
        return _ssm_cache[param_name]
    try:
        log.info(f"Leyendo parámetro de SSM: {param_name}")
        resp = ssm.get_parameter(Name=param_name, WithDecryption=True)
        data = json.loads(resp["Parameter"]["Value"])
        _ssm_cache[param_name] = data
        return data
    except (ClientError, json.JSONDecodeError) as e:
        raise RuntimeError(f"No se pudo leer/parsear el parámetro SSM '{param_name}': {e}")

# ------------------------------------------------------------------------------
# Lambda: applyWhiteBg
# ------------------------------------------------------------------------------
# ... (descripción sin cambios)
# ...
# Flujo:
# 1️⃣ Descarga el JSON (ej: processing-output/fecha/img.json)
# 2️⃣ Crea el lienzo blanco y compone la imagen.
# 3️⃣ Guarda el resultado en EL MISMO DIRECTORIO (ej: processing-output/fecha/img_B1.jpg)
# ...
# ------------------------------------------------------------------------------
def lambda_handler(event, context):
    # 1. VALIDAR CONFIGURACIÓN Y PARSEAR ENTRADA (SECCIÓN MODIFICADA)
    # ----------------------------------------------------
    try:
        Config.validate()
        log.info("Iniciando Lambda 'applyWhiteBg'. Configuración validada.")

        # Validamos que el parámetro SSM existe, aunque no usaremos su
        # contenido para construir la ruta de salida.
        get_ssm_json(Config.DIRECTORIES_MAP_PARAM)
        log.info(f"Parámetro SSM '{Config.DIRECTORIES_MAP_PARAM}' cargado.")
        
        config = event['requestBuilder']['Payload']['savedBase64Objects']['main']
        input_s3_uri = config['outputUri']
        
        configured_bucket = Config.PROCESS_IMAGES_BUCKET
        input_key = input_s3_uri.split('/', 3)[-1]
        
        # --- LÓGICA DE RUTAS MODIFICADA ---
        
        # 1. Obtener el directorio del archivo de entrada
        # Ej: processing-output/2025-10-23/image.json -> processing-output/2025-10-23
        input_dir = pp.dirname(input_key)
        
        # 2. Obtener el nombre base del archivo (sin extensión)
        # Ej: processing-output/2025-10-23/image.json -> image
        base_filename = pp.splitext(pp.basename(input_key))[0]
        
        # 3. Construir la ruta de salida final en el MISMO directorio de entrada
        # Ej: ("processing-output/2025-10-23", "image_B1.jpg") -> "processing-output/2025-10-23/image_B1.jpg"
        output_key = pp.join(input_dir, f"{base_filename}_B1.jpg")
        # --- FIN LÓGICA DE RUTAS MODIFICADA ---

        log.info(f"Bucket configurado: '{configured_bucket}'")
        log.info(f"Archivo de entrada (key): '{input_key}'")
        log.info(f"Directorio de entrada/salida detectado: '{input_dir}'")
        log.info(f"Archivo de salida final (key): '{output_key}'")

    except Exception as e:
        log.error(f"Error en la configuración o al parsear la entrada: {e}")
        raise

    # 2. DESCARGAR JSON Y DECODIFICAR IMAGEN
    # ----------------------------------------------------
    try:
        log.info(f"Descargando JSON desde: s3://{configured_bucket}/{input_key}")
        response = s3.get_object(Bucket=configured_bucket, Key=input_key)
        
        params_data = json.loads(response['Body'].read().decode('utf-8'))
        image_b64 = params_data['images'][0]
        
        img_bytes = base64.b64decode(image_b64)
        img_array = np.frombuffer(img_bytes, dtype=np.uint8)
        img_rgba = cv2.imdecode(img_array, cv2.IMREAD_UNCHANGED)
        
        if img_rgba is None or len(img_rgba.shape) < 3 or img_rgba.shape[2] != 4:
            raise ValueError("La imagen decodificada no es un PNG con canal alfa válido.")

    except Exception as e:
        log.error(f"Falla al descargar o decodificar la imagen: {e}")
        raise

    # 3. CREAR FONDO BLANCO Y COMPONER IMAGEN (Lógica sin cambios)
    # ----------------------------------------------------
    log.info(f"Creando lienzo blanco de {Config.OUTPUT_DIM}x{Config.OUTPUT_DIM}px.")
    bgr_channels = img_rgba[:, :, :3]
    alpha_channel = img_rgba[:, :, 3]
    white_background = np.full((Config.OUTPUT_DIM, Config.OUTPUT_DIM, 3), 255, dtype=np.uint8)
    h, w = bgr_channels.shape[:2]
    start_y, start_x = (Config.OUTPUT_DIM - h) // 2, (Config.OUTPUT_DIM - w) // 2
    roi = white_background[start_y:start_y+h, start_x:start_x+w]
    alpha_normalized = (alpha_channel / 255.0)[:, :, np.newaxis]
    composed_roi = (bgr_channels * alpha_normalized) + (roi * (1.0 - alpha_normalized))
    white_background[start_y:start_y+h, start_x:start_x+w] = composed_roi.astype(np.uint8)

    # 4. GUARDAR RESULTADO COMO JPG EN S3
    # ----------------------------------------------------
    log.info(f"Guardando resultado JPG en: s3://{configured_bucket}/{output_key}")
    jpeg_params = [int(cv2.IMWRITE_JPEG_QUALITY), Config.JPEG_QUALITY]
    ok, buffer = cv2.imencode(".jpg", white_background, jpeg_params)
    if not ok: 
        raise ValueError("No se pudo codificar la imagen final a formato JPG.")

    s3.put_object(
        Bucket=configured_bucket,
        Key=output_key,
        Body=buffer.tobytes(),
        ContentType='image/jpeg'
    )
    
    # 5. RETORNAR RESPUESTA DE ÉXITO
    # ----------------------------------------------------
    output_path = f"s3://{configured_bucket}/{output_key}"
    log.info(f"Éxito. Resultado disponible en: {output_path}")
    
    return {
        'status': 'WhiteBackgroundAppliedSuccess',
        'output_path': output_path
    }