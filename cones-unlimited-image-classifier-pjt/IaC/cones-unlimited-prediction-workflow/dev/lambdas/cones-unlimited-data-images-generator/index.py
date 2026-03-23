import json
import boto3
import base64
import logging

s3 = boto3.client('s3')
log = logging.getLogger()
log.setLevel(logging.INFO)

def lambda_handler(event, context):
    """A function to serialize target data from S3"""

    # Get the s3 address from the Step Function event input
    source_image = event.get("sourceImage")
    key = source_image.get("s3_key")
    bucket = source_image.get("s3_bucket")
    log.info(f"Leyendo la imagen localizada en: {bucket} / {key}")
    # Download the data from s3 to /tmp/image.png
    s3.download_file(bucket, key, "/tmp/image.png")
    
    # We read the data from a file
    with open("/tmp/image.png", "rb") as f:
        image_data = base64.b64encode(f.read())
    log.info(f"imagen descarga en /tmp/image.png y codificada en base64.")
    # Pass the data back to the Step Function
    print("Event:", event.keys())
    return {
        'statusCode': 200,
        'body': {
            "image_data": image_data,
            "s3_bucket": bucket,
            "s3_key": key,
            "inferences": []
        }
    }