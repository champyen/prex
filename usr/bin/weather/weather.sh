echo "GET /Taipei?0 HTTP/1.1" > /tmp/req.txt
echo "Host: wttr.in" >> /tmp/req.txt
echo "User-Agent: curl" >> /tmp/req.txt
echo "Connection: close" >> /tmp/req.txt
echo "" >> /tmp/req.txt
cat /tmp/req.txt
nc wttr.in 80 < /tmp/req.txt
rm /tmp/req.txt
