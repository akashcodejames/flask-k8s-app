from flask import Flask, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

@app.route('/health')
def health():
    return jsonify({"status": "healthy"}), 200

@app.route('/api/message')
def get_message():
    return jsonify({
        "message": "Hello from Flask Backend v10 (Auto-Deployed)!",
        "status": "success",
        "version": "1.1.0"
    }), 200

@app.route('/api')
def api_root():
    return jsonify({
        "message": "Flask API is running",
        "endpoints": [
            "/health",
            "/api",
            "/api/message"
        ]
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
