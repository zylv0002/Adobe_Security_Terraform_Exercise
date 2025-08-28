#!/usr/bin/env python3
"""
Smoke Test for OWASP Juice Shop WAF Configuration
Tests that the WAF is properly blocking malicious requests while allowing legitimate traffic.
"""

import argparse
import requests
import time
from urllib.parse import urljoin

def test_benign_request(url):
    """Test a benign request that should return 200 OK"""
    try:
        response = requests.get(url, timeout=10)
        print(f"Benign request to {url} - Status: {response.status_code}")
        return response.status_code == 200
    except requests.RequestException as e:
        print(f"Benign request failed: {e}")
        return False

def test_sqli_attack(url):
    """Test SQL injection attack that should be blocked with 403"""
    test_url = urljoin(url, "/rest/products/search")
    payload = {"q": "' OR 1=1--"}
    
    try:
        response = requests.get(test_url, data=payload, timeout=10)
        print(f"SQLi attack to {test_url} - Status: {response.status_code}")
        
        if response.status_code == 403:
            print("SQLi attack was properly blocked by WAF")
            return True
        else:
            print(f"SQLi attack was NOT blocked! Expected 403, got {response.status_code}")
            if response.status_code == 200:
                print("WARNING: Application may be vulnerable to SQL injection!")
            return False
            
    except requests.RequestException as e:
        print(f"SQLi test failed: {e}")
        return False

def test_xss_attack(url):
    """Test XSS attack that should be blocked (optional additional test)"""
    test_url = urljoin(url, "/search")
    payload = {"q": "<script>alert('xss')</script>"}
    
    try:
        response = requests.get(test_url, params=payload, timeout=10)
        print(f"XSS attack to {test_url} - Status: {response.status_code}")
        return response.status_code == 403  # Should be blocked
    except requests.RequestException as e:
        print(f"XSS test failed: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description='Smoke Test for WAF Configuration')
    parser.add_argument('url', help='Base URL of the application (e.g., http://alb-dns-name.com)')
    parser.add_argument('--test-xss', action='store_true', help='Also test XSS protection')
    parser.add_argument('--delay', type=int, default=2, help='Delay before starting tests in seconds')
    
    args = parser.parse_args()
    
    print(f"Starting smoke test for {args.url}")
    print("=" * 50)
    
    # Wait for services to be ready
    if args.delay > 0:
        print(f"Waiting {args.delay} seconds before starting tests...")
        time.sleep(args.delay)
    
    test_results = []
    
    # Test 1: Benign request (should succeed)
    print("\n1. Testing benign request...")
    test_results.append(("Benign Request", test_benign_request(args.url)))
    
    # Test 2: SQL injection attack (should be blocked)
    print("\n2. Testing SQL injection protection...")
    test_results.append(("SQLi Protection", test_sqli_attack(args.url)))
    
    # Test 3: Optional XSS test
    if args.test_xss:
        print("\n3. Testing XSS protection...")
        test_results.append(("XSS Protection", test_xss_attack(args.url)))
    
    # Summary
    print("\n" + "=" * 50)
    print("TEST SUMMARY:")
    print("=" * 50)
    
    all_passed = True
    for test_name, result in test_results:
        status = "PASS" if result else "FAIL"
        print(f"{status} - {test_name}")
        if not result:
            all_passed = False
    
    print("=" * 50)
    if all_passed:
        print("All smoke tests passed! WAF is functioning correctly.")
        return 0
    else:
        print("Some tests failed. Please check WAF configuration.")
        return 1

if __name__ == "__main__":
    main()