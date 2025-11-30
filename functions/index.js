/**
 * Firebase Cloud Functions - AI Spor Pro
 * Otomatik Match Pool Güncelleme
 */

const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");
const https = require("https");

// Firebase Admin initialize
admin.initializeApp();

// Global options
setGlobalOptions({ maxInstances: 10 });

/**
 * 🔥 SCHEDULED FUNCTION: Her 12 saatte bir Match Pool güncelle
 * Çalışma zamanı: 06:00 ve 18:00 (Türkiye saati UTC+3)
 */
exports.updateMatchPoolScheduled = onSchedule({
  schedule: "0 3,15 * * *", // UTC 03:00 ve 15:00 = TR 06:00 ve 18:00
  timeZone: "Europe/Istanbul",
  memory: "512MB",
  timeoutSeconds: 540, // 9 dakika
}, async (event) => {
  logger.info("🔥 Scheduled Match Pool Update başlatıldı");
  
  try {
    await updateMatchPoolLogic();
    logger.info("✅ Match Pool güncelleme başarılı");
  } catch (error) {
    logger.error("❌ Match Pool güncelleme hatası:", error);
  }
});

/**
 * 🔥 HTTP FUNCTION: Manuel Match Pool güncelleme
 * URL: https://REGION-PROJECT_ID.cloudfunctions.net/updateMatchPoolManual
 */
exports.updateMatchPoolManual = onRequest({
  memory: "512MB",
  timeoutSeconds: 540,
}, async (req, res) => {
  logger.info("🔥 Manuel Match Pool Update çağrıldı");
  
  try {
    const result = await updateMatchPoolLogic();
    res.status(200).json({
      success: true,
      message: "Match Pool güncellendi",
      ...result,
    });
  } catch (error) {
    logger.error("❌ Match Pool güncelleme hatası:", error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

/**
 * Match Pool güncelleme mantığı
 */
async function updateMatchPoolLogic() {
  const db = admin.database();
  
  // Remote Config'den API key al
  const configSnapshot = await db.ref("remoteConfig/API_FOOTBALL_KEY").get();
  const apiKey = configSnapshot.val();
  
  if (!apiKey) {
    throw new Error("API_FOOTBALL_KEY bulunamadı");
  }
  
  const now = new Date();
  const tomorrow = new Date(now);
  tomorrow.setDate(tomorrow.getDate() + 1);
  
  // Ligler
  const leagueIds = [
    203, // Türkiye Süper Lig
    39,  // İngiltere Premier League
    140, // İspanya La Liga
    78,  // Almanya Bundesliga
    135, // İtalya Serie A
    61,  // Fransa Ligue 1
  ];
  
  let totalMatches = 0;
  
  for (const leagueId of leagueIds) {
    logger.info(`📥 Lig ${leagueId} maçları çekiliyor...`);
    
    // Rate limit koruması
    await sleep(500);
    
    const matches = await fetchFixturesForLeague(
      apiKey,
      leagueId,
      formatDate(now),
      formatDate(tomorrow),
    );
    
    if (matches.length > 0) {
      // Firebase'e kaydet
      for (const match of matches) {
        const date = match.date;
        const fixtureId = match.fixtureId.toString();
        
        await db.ref(`matchPool/${date}/${fixtureId}`).set(match);
      }
      
      totalMatches += matches.length;
      logger.info(`✅ Lig ${leagueId}: ${matches.length} maç eklendi`);
    }
  }
  
  // Metadata güncelle
  await db.ref("poolMetadata").set({
    lastUpdate: admin.database.ServerValue.TIMESTAMP,
    totalMatches: totalMatches,
    leagues: leagueIds,
    nextUpdate: now.getTime() + (12 * 60 * 60 * 1000), // 12 saat sonra
  });
  
  // Eski maçları temizle (3 saatten eski)
  await cleanOldMatches(db);
  
  logger.info(`🎉 Toplam ${totalMatches} maç güncellendi`);
  
  return {
    totalMatches,
    leagues: leagueIds.length,
    timestamp: now.toISOString(),
  };
}

/**
 * Belirli bir lig için maçları çek
 */
async function fetchFixturesForLeague(apiKey, leagueId, fromDate, toDate) {
  const season = new Date().getFullYear();
  const url = `https://v3.football.api-sports.io/fixtures?league=${leagueId}&from=${fromDate}&to=${toDate}&season=${season}`;
  
  try {
    const data = await makeHttpsRequest(url, apiKey);
    const fixtures = data.response || [];
    
    const matches = [];
    
    for (const fixture of fixtures) {
      // Her maç için stats çek (rate limit dikkat!)
      await sleep(400);
      
      const homeTeamId = fixture.teams.home.id;
      const awayTeamId = fixture.teams.away.id;
      
      // Stats çek
      const homeStats = await fetchTeamStats(apiKey, homeTeamId, leagueId);
      await sleep(400);
      
      const awayStats = await fetchTeamStats(apiKey, awayTeamId, leagueId);
      await sleep(400);
      
      // H2H çek
      const h2h = await fetchH2H(apiKey, homeTeamId, awayTeamId);
      
      const match = {
        fixtureId: fixture.fixture.id,
        homeTeam: cleanTeamName(fixture.teams.home.name),
        awayTeam: cleanTeamName(fixture.teams.away.name),
        homeTeamId: homeTeamId,
        awayTeamId: awayTeamId,
        league: fixture.league.name,
        leagueId: leagueId,
        date: fixture.fixture.date.split("T")[0],
        time: fixture.fixture.date.split("T")[1].substring(0, 5),
        timestamp: new Date(fixture.fixture.date).getTime(),
        status: fixture.fixture.status.short,
        homeStats: homeStats,
        awayStats: awayStats,
        h2h: h2h,
        lastUpdated: Date.now(),
      };
      
      matches.push(match);
    }
    
    return matches;
  } catch (error) {
    logger.error(`❌ Lig ${leagueId} çekme hatası:`, error.message);
    return [];
  }
}

/**
 * Takım istatistikleri çek
 */
async function fetchTeamStats(apiKey, teamId, leagueId) {
  const season = new Date().getFullYear();
  const url = `https://v3.football.api-sports.io/teams/statistics?team=${teamId}&season=${season}&league=${leagueId}`;
  
  try {
    const data = await makeHttpsRequest(url, apiKey);
    return data.response || null;
  } catch (error) {
    logger.warn(`⚠️ Stats alınamadı (Team ${teamId}):`, error.message);
    return null;
  }
}

/**
 * H2H (Head to Head) çek
 */
async function fetchH2H(apiKey, team1Id, team2Id) {
  const url = `https://v3.football.api-sports.io/fixtures/headtohead?h2h=${team1Id}-${team2Id}`;
  
  try {
    const data = await makeHttpsRequest(url, apiKey);
    return data.response || [];
  } catch (error) {
    logger.warn(`⚠️ H2H alınamadı:`, error.message);
    return [];
  }
}

/**
 * HTTPS isteği yap
 */
function makeHttpsRequest(url, apiKey) {
  return new Promise((resolve, reject) => {
    const options = {
      headers: {
        "x-rapidapi-host": "v3.football.api-sports.io",
        "x-rapidapi-key": apiKey,
      },
    };
    
    https.get(url, options, (res) => {
      let data = "";
      
      res.on("data", (chunk) => {
        data += chunk;
      });
      
      res.on("end", () => {
        try {
          resolve(JSON.parse(data));
        } catch (error) {
          reject(new Error("JSON parse error"));
        }
      });
    }).on("error", (error) => {
      reject(error);
    });
  });
}

/**
 * Eski maçları temizle
 */
async function cleanOldMatches(db) {
  const cutoffTime = Date.now() - (3 * 60 * 60 * 1000); // 3 saat önce
  
  const snapshot = await db.ref("matchPool").get();
  
  if (snapshot.exists()) {
    let deletedCount = 0;
    const updates = {};
    
    snapshot.forEach((dateSnapshot) => {
      const date = dateSnapshot.key;
      
      dateSnapshot.forEach((matchSnapshot) => {
        const matchData = matchSnapshot.val();
        
        if (matchData.timestamp < cutoffTime) {
          updates[`matchPool/${date}/${matchSnapshot.key}`] = null;
          deletedCount++;
        }
      });
    });
    
    if (Object.keys(updates).length > 0) {
      await db.ref().update(updates);
      logger.info(`🗑️ ${deletedCount} eski maç temizlendi`);
    }
  }
}

// Helper functions
function formatDate(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function cleanTeamName(name) {
  const map = {
    "ç": "c", "Ç": "C", "ğ": "g", "Ğ": "G",
    "ı": "i", "İ": "I", "ö": "o", "Ö": "O",
    "ş": "s", "Ş": "S", "ü": "u", "Ü": "U",
  };
  
  let clean = name;
  Object.keys(map).forEach((turkish) => {
    clean = clean.replace(new RegExp(turkish, "g"), map[turkish]);
  });
  
  return clean.trim();
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
