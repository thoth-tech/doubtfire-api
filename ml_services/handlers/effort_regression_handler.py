
import json
import torch
from ts.torch_handler.base_handler import BaseHandler

class EffortRegressionHandler(BaseHandler):
    def postprocess(self, data):
        if isinstance(data, torch.Tensor):
            return {"predicted_effort": float(data.item())}
        return {"predicted_effort": data}

    def handle(self, data, context):
        try:
            # Extract request body
            body = data[0].get("body")
           
            features = body["features"]   # no json.loads

            # Convert to tensor
            tensor = torch.tensor(features).float().unsqueeze(0)

            # Run model
            
            output = max(0.0, self.model(tensor).item()) # to have positive output


            # Return JSON response
            return [json.dumps({"predicted_effort": output})]
            
        except Exception as e:
            return [json.dumps({"error": str(e)})]
