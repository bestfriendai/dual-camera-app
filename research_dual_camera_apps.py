#!/usr/bin/env python3
"""
Research script for dual camera recording apps market analysis (October 2025)
"""
import requests
import json
import time
from datetime import datetime

def search_app_store(query):
    """Search iOS App Store"""
    try:
        # iTunes Search API
        url = "https://itunes.apple.com/search"
        params = {
            "term": query,
            "country": "US",
            "entity": "software",
            "limit": 25
        }
        response = requests.get(url, params=params, timeout=10)
        if response.status_code == 200:
            return response.json()
    except Exception as e:
        print(f"App Store search error: {e}")
    return None

def get_app_details(app_id):
    """Get detailed app information"""
    try:
        url = f"https://itunes.apple.com/lookup?id={app_id}&country=US"
        response = requests.get(url, timeout=10)
        if response.status_code == 200:
            return response.json()
    except Exception as e:
        print(f"App details error: {e}")
    return None

def search_reddit(query):
    """Search Reddit for discussions"""
    try:
        url = "https://www.reddit.com/search.json"
        params = {
            "q": query,
            "limit": 10,
            "sort": "relevance",
            "t": "year"
        }
        headers = {"User-Agent": "DualCameraResearch/1.0"}
        response = requests.get(url, params=params, headers=headers, timeout=10)
        if response.status_code == 200:
            return response.json()
    except Exception as e:
        print(f"Reddit search error: {e}")
    return None

def main():
    research_data = {
        "research_date": "October 24, 2025",
        "mixcam": {},
        "competitors": [],
        "market_insights": {
            "standard_features": [],
            "innovative_features": [],
            "user_complaints": [],
            "pricing_models": [],
            "ui_trends": []
        }
    }
    
    print("=== Dual Camera Apps Market Research ===\n")
    
    # Search for Mixcam
    print("1. Researching Mixcam...")
    mixcam_results = search_app_store("mixcam dual camera")
    if mixcam_results and mixcam_results.get('results'):
        for app in mixcam_results['results']:
            if 'mixcam' in app.get('trackName', '').lower():
                research_data['mixcam'] = {
                    'name': app.get('trackName'),
                    'developer': app.get('artistName'),
                    'price': app.get('formattedPrice', 'N/A'),
                    'rating': app.get('averageUserRating', 'N/A'),
                    'rating_count': app.get('userRatingCount', 0),
                    'version': app.get('version', 'N/A'),
                    'release_date': app.get('currentVersionReleaseDate', 'N/A'),
                    'description': app.get('description', '')[:500],
                    'app_id': app.get('trackId'),
                    'bundle_id': app.get('bundleId'),
                    'size': app.get('fileSizeBytes', 'N/A'),
                    'min_ios': app.get('minimumOsVersion', 'N/A'),
                    'categories': app.get('genres', [])
                }
                print(f"   Found: {app.get('trackName')} by {app.get('artistName')}")
                print(f"   Rating: {app.get('averageUserRating')}/5 ({app.get('userRatingCount')} reviews)")
                break
    
    # Search for dual camera competitors
    print("\n2. Researching competitor apps...")
    search_terms = [
        "dual camera recording",
        "front back camera simultaneous",
        "double camera video",
        "multicam recording iOS"
    ]
    
    seen_apps = set()
    for term in search_terms:
        results = search_app_store(term)
        if results and results.get('results'):
            for app in results['results']:
                app_id = app.get('trackId')
                if app_id and app_id not in seen_apps:
                    seen_apps.add(app_id)
                    competitor = {
                        'name': app.get('trackName'),
                        'developer': app.get('artistName'),
                        'price': app.get('formattedPrice', 'N/A'),
                        'rating': app.get('averageUserRating', 'N/A'),
                        'rating_count': app.get('userRatingCount', 0),
                        'version': app.get('version', 'N/A'),
                        'description_snippet': app.get('description', '')[:200],
                        'categories': app.get('genres', [])
                    }
                    research_data['competitors'].append(competitor)
                    print(f"   - {app.get('trackName')} ({app.get('formattedPrice')})")
        time.sleep(0.5)
    
    # Sort competitors by rating and review count
    research_data['competitors'] = sorted(
        research_data['competitors'], 
        key=lambda x: (x.get('rating', 0), x.get('rating_count', 0)), 
        reverse=True
    )[:10]
    
    # Search Reddit for user discussions
    print("\n3. Searching Reddit for user insights...")
    reddit_queries = [
        "dual camera app iOS 2025",
        "mixcam app review",
        "best dual camera recording app"
    ]
    
    for query in reddit_queries:
        reddit_data = search_reddit(query)
        if reddit_data and reddit_data.get('data', {}).get('children'):
            for post in reddit_data['data']['children'][:3]:
                post_data = post.get('data', {})
                title = post_data.get('title', '')
                selftext = post_data.get('selftext', '')
                print(f"   - Reddit: {title[:80]}...")
        time.sleep(1)
    
    # Save research data
    output_file = "/home/ubuntu/.research_files/app_store_data.json"
    with open(output_file, 'w') as f:
        json.dump(research_data, f, indent=2)
    
    print(f"\n✓ Research data saved to {output_file}")
    print(f"\nSummary:")
    print(f"  - Mixcam data: {'Found' if research_data['mixcam'] else 'Not found'}")
    print(f"  - Competitors found: {len(research_data['competitors'])}")
    
    return research_data

if __name__ == "__main__":
    main()
