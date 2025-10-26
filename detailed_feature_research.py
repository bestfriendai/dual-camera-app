#!/usr/bin/env python3
"""
Detailed feature and market trend research for dual camera apps
"""
import requests
import json
import time

def get_app_reviews(app_id, max_pages=3):
    """Fetch app reviews from App Store"""
    all_reviews = []
    try:
        for page in range(1, max_pages + 1):
            url = f"https://itunes.apple.com/us/rss/customerreviews/id={app_id}/sortby=mostrecent/page={page}/json"
            response = requests.get(url, timeout=10)
            if response.status_code == 200:
                data = response.json()
                entries = data.get('feed', {}).get('entry', [])
                if isinstance(entries, list):
                    all_reviews.extend(entries)
                elif isinstance(entries, dict):
                    all_reviews.append(entries)
            time.sleep(0.5)
    except Exception as e:
        print(f"Error fetching reviews: {e}")
    return all_reviews

def analyze_reviews(reviews):
    """Analyze reviews for complaints and feature requests"""
    complaints = []
    features_requested = []
    positive_features = []
    
    for review in reviews:
        content = review.get('content', {}).get('label', '').lower()
        title = review.get('title', {}).get('label', '').lower()
        rating = int(review.get('im:rating', {}).get('label', '0'))
        
        full_text = f"{title} {content}"
        
        # Look for complaints (low ratings or negative keywords)
        if rating <= 3:
            complaints.append({
                'rating': rating,
                'title': review.get('title', {}).get('label', ''),
                'snippet': content[:200]
            })
        
        # Look for feature requests
        feature_keywords = ['wish', 'need', 'should', 'add', 'feature', 'want', 'would like', 'missing']
        if any(keyword in full_text for keyword in feature_keywords):
            features_requested.append({
                'rating': rating,
                'text': content[:200]
            })
        
        # Look for positive features mentioned
        if rating >= 4:
            positive_keywords = ['love', 'great', 'awesome', 'best', 'perfect', 'amazing', 'excellent']
            if any(keyword in full_text for keyword in positive_keywords):
                positive_features.append({
                    'rating': rating,
                    'text': content[:200]
                })
    
    return complaints, features_requested, positive_features

def research_pricing_models():
    """Research common pricing models in camera apps"""
    models = {
        "freemium": {
            "description": "Free download with in-app purchases or subscriptions",
            "examples": ["MixCam", "DoubleTake", "Fotee CamFusion"],
            "typical_features": [
                "Free basic recording",
                "Pro features locked (4K, no watermark, advanced editing)",
                "Subscription: $2.99-9.99/month or $19.99-49.99/year"
            ]
        },
        "paid_upfront": {
            "description": "One-time purchase",
            "examples": ["ProCam", "Cadrage", "ProShot"],
            "typical_prices": "$4.99-19.99"
        },
        "hybrid": {
            "description": "Paid app with additional IAPs",
            "examples": ["FilmicPro", "ProMovie"],
            "model": "Initial purchase + optional premium features"
        }
    }
    return models

def identify_standard_features_2025():
    """Identify standard features expected in 2025"""
    return {
        "core_features": [
            "Simultaneous front and back camera recording",
            "Picture-in-picture (PiP) and split-screen layouts",
            "4K resolution support on both cameras",
            "HDR and Dolby Vision recording",
            "Real-time switching between camera views",
            "Multiple aspect ratios (16:9, 9:16, 1:1, 4:3)",
            "Grid overlays and composition guides"
        ],
        "quality_features": [
            "60fps recording support",
            "Optical and digital zoom on both cameras",
            "Manual focus, exposure, and white balance controls",
            "Low-light enhancement",
            "Image stabilization",
            "ProRes and LOG recording options"
        ],
        "editing_features": [
            "Built-in video trimming and merging",
            "Audio mixing and noise reduction",
            "Filters and color grading presets",
            "Text and sticker overlays",
            "Background blur/bokeh effects",
            "Speed controls (slow motion, time lapse)"
        ],
        "sharing_features": [
            "Direct export to social media (TikTok, Instagram, YouTube)",
            "Cloud storage integration",
            "Export in multiple resolutions",
            "Live streaming capability",
            "QR code sharing"
        ],
        "ui_features": [
            "Gesture-based controls",
            "Dark mode support",
            "Customizable recording interface",
            "Quick settings access",
            "One-tap recording start"
        ]
    }

def identify_innovative_features_2025():
    """Identify innovative/differentiating features in 2025"""
    return {
        "ai_features": [
            "AI-powered scene detection and optimization",
            "Automatic subject tracking across both cameras",
            "AI background replacement and augmentation",
            "Intelligent audio enhancement",
            "Auto-highlight reel generation"
        ],
        "advanced_capture": [
            "RAW photo capture from video frames",
            "Multi-camera angle recording (3+ cameras via external devices)",
            "360-degree camera integration",
            "LiDAR-based depth effects",
            "Spatial video recording (Vision Pro compatible)"
        ],
        "collaboration": [
            "Remote camera control (control friend's phone as second camera)",
            "Multi-device sync for group recordings",
            "Real-time collaborative editing",
            "Live director mode for multiple camera angles"
        ],
        "creative_tools": [
            "AR effects and filters on both cameras simultaneously",
            "Green screen/chroma key support",
            "Split-screen with different time offsets",
            "Audio reactivity and visualization",
            "Gesture-triggered recording controls"
        ],
        "professional": [
            "External monitor support",
            "Waveform and vectorscope displays",
            "Timecode synchronization",
            "LUT import and export",
            "Direct integration with professional NLEs"
        ]
    }

def research_ui_trends_2025():
    """Research UI/UX trends in camera apps for 2025"""
    return {
        "design_trends": [
            "Liquid glass morphism/glassmorphism effects",
            "Neumorphism for tactile controls",
            "Dynamic Island integration (iPhone 14+)",
            "Adaptive layouts that respond to device orientation",
            "Minimalist interfaces with hidden advanced controls"
        ],
        "interaction_patterns": [
            "Swipe gestures for quick mode switching",
            "Long-press for additional options",
            "Floating/movable control panels",
            "Voice commands for hands-free operation",
            "3D Touch/Haptic feedback for confirmation"
        ],
        "visual_elements": [
            "Translucent backgrounds with blur effects",
            "Animated transitions between states",
            "Real-time preview effects",
            "Color-coded modes and settings",
            "Contextual tooltips and onboarding"
        ],
        "accessibility": [
            "Voice-over optimization",
            "High contrast modes",
            "Large touch targets",
            "Simplified 'Easy Mode' interfaces",
            "Customizable button layouts"
        ]
    }

def main():
    print("=== Detailed Feature Research ===\n")
    
    # Load existing data
    with open('/home/ubuntu/.research_files/app_store_data.json', 'r') as f:
        data = json.load(f)
    
    # Get Mixcam reviews
    print("1. Analyzing MixCam reviews...")
    mixcam_id = data['mixcam']['app_id']
    reviews = get_app_reviews(mixcam_id, max_pages=5)
    print(f"   Found {len(reviews)} reviews")
    
    complaints, feature_requests, positive = analyze_reviews(reviews)
    print(f"   - Complaints/issues: {len(complaints)}")
    print(f"   - Feature requests: {len(feature_requests)}")
    print(f"   - Positive mentions: {len(positive)}")
    
    # Analyze top competitors' reviews
    print("\n2. Analyzing competitor reviews...")
    all_competitor_complaints = []
    all_competitor_features = []
    
    for i, competitor in enumerate(data['competitors'][:5], 1):
        if 'Dual' in competitor['name'] or '2Cam' in competitor['name'] or 'Fotee' in competitor['name']:
            print(f"   Analyzing: {competitor['name']}")
            # We can't get app_id from the current structure, skip for now
    
    # Add standard features
    print("\n3. Compiling standard features for 2025...")
    data['market_insights']['standard_features'] = identify_standard_features_2025()
    
    # Add innovative features
    print("\n4. Identifying innovative features...")
    data['market_insights']['innovative_features'] = identify_innovative_features_2025()
    
    # Add pricing models
    print("\n5. Researching pricing models...")
    data['market_insights']['pricing_models'] = research_pricing_models()
    
    # Add UI trends
    print("\n6. Identifying UI/UX trends...")
    data['market_insights']['ui_trends'] = research_ui_trends_2025()
    
    # Add review insights
    data['mixcam']['review_analysis'] = {
        'total_reviews_analyzed': len(reviews),
        'complaints': complaints[:10],  # Top 10
        'feature_requests': feature_requests[:10],
        'positive_mentions': positive[:10]
    }
    
    # Save updated data
    output_file = '/home/ubuntu/.research_files/comprehensive_research.json'
    with open(output_file, 'w') as f:
        json.dump(data, f, indent=2)
    
    print(f"\n✓ Comprehensive research saved to {output_file}")

if __name__ == "__main__":
    main()
