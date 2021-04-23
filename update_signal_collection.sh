PROXY="http://localhost:6764"
APP="YOUR_FUSION_APP_ID"
curl -u $CREDS -X POST "$PROXY/api/update/all/signalCollection"