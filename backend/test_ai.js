const http = require("http");

const data = JSON.stringify({
  homeTeam: "Arezzo",
  awayTeam: "Union Brescia",
  matchDate: "2026-08-11",
  statistics: {
    note: "Test iniziale SmartBet AI"
  }
});

const options = {
  hostname: "localhost",
  port: 3000,
  path: "/analyze",
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(data)
  }
};

const req = http.request(options, (res) => {
  let body = "";

  res.on("data", (chunk) => {
    body += chunk;
  });

  res.on("end", () => {
    console.log("");
    console.log("========================================");
    console.log("SMARTBET AI - RISULTATO TEST");
    console.log("========================================");
    console.log("");
    console.log(body);
    console.log("");
    console.log("========================================");
  });
});

req.on("error", (error) => {
  console.error("ERRORE:", error.message);
});

req.write(data);
req.end();