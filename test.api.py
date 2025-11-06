# test_api.py
import requests
import json

# This is the endpoint for your CodeGenius walker
API_URL = "http://localhost:8000/walker/CodeGenius"

PAYLOAD = {
    "repo_url": "https://github.com/jaseci-labs/jaclang"
}

print(f"Sending request to {API_URL}...")
print(f"Payload: {json.dumps(PAYLOAD, indent=2)}")

try:
    response = requests.post(API_URL, json=PAYLOAD, timeout=300)

    if response.status_code == 200:
        print("\nSuccess! Response from Jac Server:")
        print(json.dumps(response.json(), indent=2))
    else:
        print(f"\nError: {response.status_code}")
        print(response.text)

except requests.exceptions.ConnectionError:
    print("\nConnection Error: Failed to connect.")
    print("Is your 'jac serve main.jac' server running in another terminal?")