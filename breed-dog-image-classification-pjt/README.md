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

The best trainig hyperparameters are those that minize the `Test Loss` metric

- A screenshot of completed hyperparameter tuning job:}

- Logged metrics during the training process:

| TrainingJobName                               | batch_size   |   learning_rate |   Test Loss |   TrainingTime |
|:----------------------------------------------|:-------------|----------------:|------------:|---------------:|
| pytorch-dog-breed-hp-260404-2324-004-77f9654d | "256"        |      0.021611   |     2.6197  |           1365 |
| pytorch-dog-breed-hp-260404-2324-003-7c43aba1 | "64"         |      0.091363   |     18.9740  |           1222 |
| pytorch-dog-breed-hp-260404-2324-002-3ec2c4c9 | "128"        |      0.002274   |     .7775  |           1381 |
| pytorch-dog-breed-hp-260404-2324-001-e098a150 | "128"        |      0.017384   |     1.9084  |           1370 |

- Best hyperparameters: `batch_size` = 128 and `learning_rate` = 0.002274


## Debugging and Profiling
To monitor the model, I configured SageMaker Debugger and Profiler in the Estimator with the client library `SMDebug`. 

**Profiler:** Set up to monitor CPU and GPU utilization (`system_monitor_interval_millis=500`) to ensure there were no bottlenecks during the data loading phase.
**Debugger:** Configured `DebuggerHookConfig` to capture the `CrossEntropyLoss` during both training and evaluation.

### Anomalous Behavior and Debugging Steps
During the debugging phase, two main issues were encountered and resolved:

1. **Incomplete Loss Curves (Debugger Issue):** Initially, the debugger only plotted 1 or 2 data points for the entire training process.
   * *Debugging Step:* Discovered that default built-in rules (like `loss_not_decreasing`) forced a `save_interval` of 500 steps. Since the dog breed dataset only had about 53 steps per epoch, the debugger was missing the data. I debugged this by removing the conflicting rules and using a custom `CollectionConfig` with `"train.save_interval": "10"` and `"eval.save_interval": "10"` to capture granular data.
2. **Endpoint Timeout (Inference Issue):** The deployed endpoint returned a `Timeout` error when queried.
   * *Debugging Step:* Checked CloudWatch logs and identified the container was hanging. The issue was traced to `models.resnet50(pretrained=True)` in `inference.py`, which tried to download 100MB of weights from the internet at runtime. Fixed by changing it to `pretrained=False` and correctly loading the local `model.pth` state dictionary.

### Results
The profiling and debugging process yielded valuable insights. The captured `CrossEntropyLoss` plot revealed high variance/noise during the validation phase.

![Cross Entropy Loss Plot]([INSERT IMAGE HERE: Path to your saved plot image])

* **Insight from the plot:** The validation loss (orange line) fluctuates heavily compared to the training loss. This is indicative of "mini-batch noise" caused by a relatively high learning rate or challenging distinct image batches. Furthermore, the training stopped early around step 1600 (Epoch 9). This demonstrates that the SageMaker rules properly identified the erratic validation loss and triggered Early Stopping to prevent severe overfitting and save compute resources.
* **Profiler Insights:** The profiler report indicated that GPU utilization was optimal and data-loading wasn't a severe bottleneck, meaning the instance type (`ml.g4dn.xlarge`) was well-suited for the task.

*(Remember to provide the profiler html/pdf file in your submission).*

## Model Deployment
The model was deployed using a SageMaker `PyTorchModel` object with a custom `inference.py` script. The endpoint uses an `ml.m5.large` instance and is configured to accept `image/jpeg` payload types via an `IdentitySerializer`.

*([INSERT IMAGE HERE: Screenshot of the deployed active endpoint in SageMaker Console])*

### Code sample for querying the model endpoint
To query the endpoint, you can pass the raw bytes of an image to the predictor:

```python
import requests
import io
import numpy as np
from PIL import Image

# 1. Download a test image
image_url = "[https://www.akc.org/wp-content/uploads/2017/11/Affenpinscher-running-outdoors.jpg](https://www.akc.org/wp-content/uploads/2017/11/Affenpinscher-running-outdoors.jpg)"
response_img = requests.get(image_url)
image_bytes = response_img.content

# 2. Query the endpoint
# Ensure the predictor is configured with IdentitySerializer(content_type="image/jpeg")
response = predictor.predict(image_bytes, initial_args={"ContentType": "image/jpeg"})

# 3. Process the response
logits = np.array(response[0])
predicted_class_index = np.argmax(logits)
print(f"Predicted Dog Breed Class Index: {predicted_class_index}")