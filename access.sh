#!/bin/bash

# Quick Access Script for Flask K8s Application
# This script sets up port-forwarding to access the app at http://localhost:8080

echo "🚀 Flask K8s Application - Quick Access"
echo ""
echo "Setting up port-forward to access your application..."
echo ""
echo "✅ Your application will be available at:"
echo "   http://localhost:8080"
echo ""
echo "Press Ctrl+C to stop the port-forward"
echo ""

kubectl port-forward -n flask-app svc/frontend-service 8080:80
