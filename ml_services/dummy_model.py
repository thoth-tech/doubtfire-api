import torch
import torch.nn as nn

class EffortPredictor(nn.Module):
    def __init__(self, input_dim):
        super(EffortPredictor, self).__init__()
        self.fc = nn.Linear(input_dim, 1)

    def forward(self, x):
        return self.fc(x)

# Create a dummy model with 10 input features
model = EffortPredictor(input_dim=10)

# Save its state dict as effort_model.pth
torch.save(model.state_dict(), "effort_model.pth")
