import torch
import torch.nn as nn

class EffortPredictor(nn.Module):
    def __init__(self, input_dim=10): # initialise with a default value
        super(EffortPredictor, self).__init__()
        self.fc = nn.Linear(input_dim, 1)

    def forward(self, x):
        return self.fc(x)

def get_model():
    model = EffortPredictor(input_dim=10)  # adjust to your features
    model.load_state_dict(torch.load("effort_model.pth"))
    model.eval()
    return model
