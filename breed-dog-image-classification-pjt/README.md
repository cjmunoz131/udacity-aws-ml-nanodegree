# Image Classification using AWS SageMaker

This project uses AWS SageMaker to fine-tune a pretrained ResNet50 model to perform image classification on a Dog Breed dataset. The project demonstrates the application of MLOps best practices, including hyperparameter tuning, model debugging, system profiling, and deploying an active endpoint for inference.

## Project Set Up and Installation
1. Enter AWS through the gateway in the Udacity course and open SageMaker Studio.
2. Clone the project repository and navigate to the project folder.
3. Download the Dog Breed classification dataset and extract it.
4. Upload the dataset to an AWS S3 bucket so that SageMaker can access it during the training jobs.
5. Install necessary dependencies in the SageMaker notebook environment (Python 3.8, Pytorch, boto3, SMDebug, aws cli, etc)

## AWS Execution Role
The AWS execution role used for this project should have the following access:
- AmazonSageMakerFullAccess
- AmazonS3FullAccess

## Files Explanation
* `train_and_deploy.ipynb`: The main Jupyter Notebook that orchestrates the entire ML workflow, from uploading data to S3, configuring Hyperparameter Tuning jobs, setting up the Debugger/Profiler, and deploying the endpoint.
* `hpo.py`: The entry-point script for Hyperparameter Optimization. It contains the model architecture and the training loop adapted to accept dynamic hyperparameters passed by SageMaker.
* `train_model.py`: The main training script used after extracting the best hyperparameters. It includes the SageMaker Debugger and Profiler hooks (`smdebug`) to track the `CrossEntropyLoss` and system metrics at the batch/step level.
* `inference.py`: The script used for deploying the model. It defines `model_fn` (to load the saved weights), `input_fn` (to preprocess the incoming JPEG bytes into PyTorch tensors), and `predict_fn` (to perform the forward pass).

## Dataset
The dataset used for this project is the Dog Breed classification dataset, which contains images of 133 different dog breeds. The dataset is organized into three folders: `train`, `valid`, and `test`, each containing subfolders for each breed with the corresponding images.
```
data-dir
├── train
│   ├── Label 001
│   │   ├── image_01.jpg
│   │   └── image_02.jpg
│   ├── Label 002
│   │   ├── image_01.jpg
│   │   └── image_02.jpg
│   └── ...
├── valid
│   ├── Label 001
│   │   ├── image_01.jpg
│   │   └── image_02.jpg
│   ├── Label 002
│   │   ├── image_01.jpg
│   │   └── image_02.jpg
│   └── ...
└── test
    ├── Label 001
    │   ├── image_01.jpg
    │   └── image_02.jpg
    ├── Label 002
    │   ├── image_01.jpg
    │   └── image_02.jpg
    └── ...
```

### Access
The data was uploaded to an S3 bucket using the `sagemaker.Session().upload_data()` method. The S3 URI waws then passed as data channel (`data`) to the PyTorch Estimators.

## Hyperparameter Tuning
**Model Choice:** A pretrained **ResNet50** was chosen for this experiment. Transfer learning is highly effective for image classification tasks. By freezing the convolutional layers and only training a new fully connected layer, the model can leverage previously learned feature representations (edges, textures, shapes), significantly reducing training time and improving accuracy on the dog breed dataset.

**Hyperparameters Searched:**
* **Learning Rate (`lr`):** Continuous parameter ranging from `0.001` to `0.1`.
* **Batch Size (`batch-size`):** Categorical parameter choosing between `32`, `64`, `128`, `256` and `512` .
* **Epochs (`epochs`):** `2` (for the tuning phase to save compute time).

- A screenshot of all completed hyperparameter tuning jobs:

![Hyperparameter Tuning Job](./screenshots/hyperparameter-tuning-all-jobs.jpeg?raw=true "Completed Hyperparameter Tuning Job")

- Logged metrics during the training process:

The best trainig hyperparameters are those that minize the `Average Test Loss` metric

- A screenshot of completed hyperparameter tuning job:}

- Logged metrics during the training process:

| TrainingJobName                               | batch_size   |   learning_rate |   Test Loss |   TrainingTime |
|:----------------------------------------------|:-------------|----------------:|------------:|---------------:|
| pytorch-dog-breed-hp-260404-2324-004-77f9654d | "256"        |      0.021611   |     2.6197  |           1365 |
| pytorch-dog-breed-hp-260404-2324-003-7c43aba1 | "64"         |      0.091363   |     18.9740  |           1222 |
| pytorch-dog-breed-hp-260404-2324-002-3ec2c4c9 | "128"        |      0.002274   |      0.7775  |           1381 |
| pytorch-dog-breed-hp-260404-2324-001-e098a150 | "128"        |      0.017384   |     1.9084  |           1370 |

- Best hyperparameters: `batch_size` = 128 and `learning_rate` = 0.002274

- A screenshot of the best hyperparameter tuning job:

![Hyperparameter Tuning Job](./screenshots/hyperparameter-tuning-best-job.jpeg?raw=true "Completed Hyperparameter Tuning Job")

## Debugging and Profiling
To monitor the model, We configured SageMaker Debugger and Profiler in the Estimator with the client library `SMDebug`. 

**Profiler:** Set up to monitor CPU and GPU utilization (`system_monitor_interval_millis=500`) to ensure there were no bottlenecks during the training phase.
**Debugger:** Configured `DebuggerHookConfig` to capture the `CrossEntropyLoss` during both training and evaluation. Sagemaker debugger is used to monitor the performance of the machine learning training phase, it records training and evaluation metrics that can be used to check and identify different problems liber overfitting, overtraining, poor weight initialization and vanishing gradients.

### Anomalous Behavior and Debugging Steps
During the debugging phase, two main issues were encountered and resolved:

1. **Incomplete Loss Curves (Debugger Issue):** Initially, the debugger only plotted 1 or 2 data points for the entire training process.
   * *Debugging Step:* Discovered that default built-in rules (like `loss_not_decreasing`) forced a `save_interval` of 500 steps. Since the dog breed dataset only had about 53 steps per epoch, the debugger was missing the data. I debugged this by removing the conflicting rules and using a custom `CollectionConfig` with `"train.save_interval": "100"` and `"eval.save_interval": "15"` to capture granular data.
2. **Endpoint Timeout (Inference Issue):** The deployed endpoint returned a `Timeout` error when queried.
   * *Debugging Step:* Checked CloudWatch logs and identified the container was hanging. The issue was traced to `models.resnet50(pretrained=True)` in `inference.py`, which tried to download 100MB of weights from the internet at runtime. Fixed by changing it to `pretrained=False` and correctly loading the local `model.pth` state dictionary.

### Results
The profiling and debugging process yielded valuable insights. The captured `CrossEntropyLoss` plot revealed high variance/noise during the validation phase.

![Cross Entropy Loss Plot](./screenshots/output.png?raw=true)

* **Insight from the plot:** The generated loss plot provides a clear visualization of the model's learning process and reveals a classic case of overfitting.

**Analysis of the Graph**:

- Training Loss (Blue Line): The cross-entropy loss on the training set drops sharply during the initial 100 steps and continues to decrease steadily toward zero. This indicates that the pre-trained ResNet50 model is highly capable and has successfully learned the features of the training images.

- Validation Loss (Orange Line): In contrast, the validation loss plateaus very early in the training process. Instead of following the training loss downward, it remains flat and even begins to slowly increase after step 100.

Conclusion: The widening gap between the training loss and the validation loss demonstrates that the model is memorizing the training data (overfitting) rather than generalizing well to unseen images. The high capacity of the ResNet50 architecture allows it to easily memorize the relatively limited dog breed dataset.

Proposed Steps for Improvement:
To mitigate this anomalous behavior and improve the model's generalization capabilities, the following steps would be taken:

1. Data Augmentation: Apply random transformations to the training data pipeline (such as transforms.RandomHorizontalFlip, transforms.RandomRotation, and transforms.RandomResizedCrop). This ensures the model never sees the exact same image twice, forcing it to learn robust, generalized features of the dog breeds rather than memorizing specific pixels.

2. Dropout Regularization: Introduce a Dropout layer (e.g., nn.Dropout(p=0.5)) in the custom fully connected classification head. This randomly disables a percentage of neurons during training, preventing the network from becoming overly reliant on specific pathways and reducing memorization.

3. Early Stopping and Tolerance Adjustment: Continue leveraging SageMaker Debugger rules (like loss_not_decreasing or overfit) or framework-level configurations to actively monitor the validation metric. Additionally, reduce the tolerance iterations (patience parameter) required for the loss reduction. By doing so, the training job will automatically halt much faster as soon as the validation loss begins to rise or plateaus, effectively saving compute resources and retaining the best-performing model weights before severe overfitting occurs.

4. Learning Rate Scheduler: Implement a learning rate scheduler to dynamically reduce the learning rate as the epochs progress. This would help the optimizer converge more smoothly without bouncing around the optimal weights.

* **Profiler Insights:** The profiler report indicated that GPU utilization was optimal and the model training wasn't in a severe bottleneck, meaning the instance type (`ml.p3.2xlarge`) was well-suited for the task.

Profiler results are included and can be found in [ProfilerReport/profiler-output/](./ProfilerReport/profiler-output/)

## Model Deployment
The model was deployed using a SageMaker `PyTorchModel` object with a custom `inference.py` script. The endpoint uses an `ml.m5.large` instance and is configured to accept `image/jpeg` payload types via an `IdentitySerializer`.

![Model deployment](./screenshots/endpoint-used-in-the-test.jpeg?raw=true)

### Code sample for querying the model endpoint
To query the endpoint, you can pass the raw bytes of an image to the predictor:

```python
import requests
import io
import numpy as np
import matplotlib.pyplot as plt
from PIL import Image

def softmax(x):
    """softmax calculation."""
    e_x = np.exp(x - np.max(x))
    return e_x / e_x.sum(axis=0)

def test_model_with_url(url, ground_truth):
    """
        Download image from URL, perform inference, and display results.
    """
    print(f"\nGround Truth: {ground_truth}")
    
    try:
        # 1. Download the image
        response_img = requests.get(url, timeout=10)
        if response_img.status_code != 200:
            print(f"Error in download: {url}")
            return
        
        image_bytes = response_img.content
        
        # 2. Inference
        # Execute predictor with IdentitySerializer(content_type="image/jpeg")
        response = predictor.predict(image_bytes, initial_args={"ContentType": "image/jpeg"})
        
        # 3. Processing logits and apply softmax
        logits = np.array(response[0])
        probabilities = softmax(logits)
        
        predicted_index = np.argmax(logits)
        predicted_name = dog_names[predicted_index]
        confidence = probabilities[predicted_index]
        
        # 4. Visualization
        img = Image.open(io.BytesIO(image_bytes))
        plt.figure(figsize=(6, 4))
        plt.imshow(img)
        plt.title(f"Predicted: {predicted_name} ({confidence*100:.2f}%)\nReal: {ground_truth}")
        plt.axis('off')
        plt.show()
        
        # 5. Report
        print(f"Result -> Prediction: {predicted_name} | Probability: {confidence:.4f}")
        
    except Exception as e:
        print(f"Error in the test: {e}")
# --- SAMPLES ---
test_samples = [
    {
        "url": "https://www.akc.org/wp-content/uploads/2017/11/Affenpinscher-running-outdoors.jpg",
        "label": "Affenpinscher"
    },
    {
        "url": "https://www.akc.org/wp-content/uploads/2017/11/Chihuahua-at-the-AKC-National-Championship.jpg",
        "label": "Chihuahua"
    },
    {
        "url": "https://www.akc.org/wp-content/uploads/2018/04/chow-chow-closeup-portrait-drooling.jpg",
        "label": "Chow_chow"
    },
    {
        "url": "https://www.akc.org/wp-content/uploads/2017/11/Beagle-laying-down-in-the-shade-outdoors.jpg",
        "label": "Beagle"
    },
    {
        "url": "https://www.akc.org/wp-content/uploads/2017/11/Dalmatian-running-across-the-grass.jpg",
        "label": "Dalmatian"
    }
]

for sample in test_samples:
    test_model_with_url(sample['url'], sample['label'])