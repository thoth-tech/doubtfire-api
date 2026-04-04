# from ts.torch_handler.base_handler import BaseHandler
# import torch

# class EffortRegressionHandler(BaseHandler):
#     def postprocess(self, data):
#         if isinstance(data, torch.Tensor):
#             return {"predicted_effort": float(data.item())}
#         return {"predicted_effort": data}

#     def handle(self, data, context):
#     try:
#         body = data[0].get("body")
#         features = json.loads(body)["features"]
#         tensor = torch.tensor(features).float().unsqueeze(0)
#         output = self.model(tensor).item()
#         return [json.dumps({"predicted_effort": output})]
#     except Exception as e:
#         return [json.dumps({"error": str(e)})]

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
            #features = json.loads(body)["features"]
            features = body["features"]   # no json.loads

            # Convert to tensor
            tensor = torch.tensor(features).float().unsqueeze(0)

            # Run model
            #output = self.model(tensor).item()
            output = max(0.0, self.model(tensor).item()) # to have positive output


            # Return JSON response
            return [json.dumps({"predicted_effort": output})]
            # Return a dict inside a list (TorchServe will JSON‑serialize it)
            #return [{"predicted_effort": output}] #modify to validate output in swagger
        except Exception as e:
            return [json.dumps({"error": str(e)})]
