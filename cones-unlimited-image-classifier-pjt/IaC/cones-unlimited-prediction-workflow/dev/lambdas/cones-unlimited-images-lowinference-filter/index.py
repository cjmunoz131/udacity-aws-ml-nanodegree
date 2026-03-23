import json
import logging
import os

THRESHOLD = float(os.environ.get('THRESHOLD', .75))

log = logging.getLogger()
log.setLevel(logging.INFO)

def lambda_handler(event, context):

    # Grab the inferences from the event
    inferences = event["sourceImage"]["inferences"]

    probabilities = json.loads(inferences)
    
    # 2. Encontrar la probabilidad más alta (el score de la predicción)
    best_probability = max(probabilities)
    
    # Encontrar el índice de la clase con mayor probabilidad
    predict_class_idx = probabilities.index(best_probability)
    
    # Mapeo de clases (ajusta según el orden de tu entrenamiento)
    classes = ["motocicleta", "bicicleta"]
    prediction = classes[predict_class_idx]
    
    log.info(f"Predicción: {prediction} con probabilidad de {best_probability}")
    meets_threshold = best_probability >= THRESHOLD
    # 3. Lógica de filtrado por umbral
    if meets_threshold:
        log.info(f"STATUS: CONFIDENT ")
        event["status"] = "CONFIDENT"
        event["prediction"] = prediction
        event["confidence"] = best_probability
        pass
    else:
        log.info(f"STATUS: LOW_CONFIDENCE ")
        event["status"] = "LOW_CONFIDENCE"
        event["prediction"] = "unknown"
        event["confidence"] = best_probability
        raise("THRESHOLD_CONFIDENCE_NOT_MET")
    
    return {
        'statusCode': 200,
        'body': json.dumps(event)
    }