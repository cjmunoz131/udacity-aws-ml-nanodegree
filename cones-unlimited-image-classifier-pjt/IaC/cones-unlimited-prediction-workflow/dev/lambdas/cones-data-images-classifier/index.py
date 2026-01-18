import json
import sagemaker
import base64
import os
from sagemaker.serializers import IdentitySerializer
import logging
import boto3
from botocore.exceptions import ClientError

log = logging.getLogger()
log.setLevel(logging.INFO)
ssm = boto3.client("ssm")

model_deployment_dict = os.environ.get('MODEL_DEPLOYMENT_DICT', '/cones-unlimited/model-deployment-dict')

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

ENDPOINT = get_ssm_json(model_deployment_dict).get('model_endpoint')

def lambda_handler(event, context):
    log.info(f"Decoding the image data.....")
    # Decode the image data
    image = base64.b64decode(event["sourceImage"]["image_data"])

    # Instantiate a Predictor
    predictor = sagemaker.predictor.Predictor(endpoint_name=ENDPOINT)

    # For this model the IdentitySerializer needs to be "image/png"
    predictor.serializer = IdentitySerializer("image/png")
    
    log.info(f"Making the prediction for the image.....")
    # Make a prediction:
    inferences = predictor.predict(image)
    
    # We return the data back to the Step Function    
    event["inferences"] = inferences.decode('utf-8')
    log.info(f"The inferences in base64 format: {event["inferences"]}")
    return {
        'statusCode': 200,
        'body': json.dumps(event)
    }