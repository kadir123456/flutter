/**
 * Firebase Cloud Functions - AI Spor Pro
 * Otomatik Match Pool Güncelleme
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const https = require("https");

// Firebase Admin initialize
admin.initializeApp();

/**
 * 🔥 SCHEDULED FUNCTION: Her 12 saatte bir Match Pool güncelle
 * Çalışma zamanı: 06:00 ve 18:00 (Türkiye saati UTC+3)
 * NOT: Spark (free) plan için scheduled functions çalışmaz
 * Şimdilik yorumda, ileride Blaze plan ile aktifleştirilebilir
 */
// exports.updateMatchPoolScheduled = functions.pubsub
//     .schedule("0 3,15 * * *")
//     .timeZone("Europe/Istanbul")
//     .onRun(async (context) => {
//       functions.logger.info(
//           "🔥 Scheduled Match Pool Update başlatıldı",
//       );
//
//       try {
//         await updateMatchPoolLogic();
//         functions.logger.info("✅ Match Pool güncelleme başarılı");
//       } catch (error) {
//         functions.logger.error(
//             "❌ Match Pool güncelleme hatası:",
//             error,
//         );
//       }
//     });

/**
 * 🔥 HTTP FUNCTION: Manuel Match Pool güncelleme
 * URL: https://REGION-PROJECT_ID.cloudfunctions.net/updateMatchPoolManual
 */
exports.updateMatchPoolManual = functions.https
    .onRequest(async (req, res) => {
      functions.logger.info("🔥 Manuel Match Pool Update çağrıldı");

      try {
        const result = await updateMatchPoolLogic();
        res.status(200).json({
          success: true,
          message: "Match Pool güncellendi",
          ...result,
        });
      } catch (error) {
        functions.logger.error(
            "❌ Match Pool güncelleme hatası:",
            error,
        );
        res.status(500).json({
          success: false,
          error: error.message,
        });
      }
    });

/**
 * Match Pool güncelleme mantığı - TÜM MAÇLAR
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

  let totalMatches = 0;
  const uniqueLeagues = new Set();

  // BUGÜN'ÜN TÜM MAÇLARINI ÇEK
  functions.logger.info("📥 Bugün oynanan tüm maçlar çekiliyor...");
  const todayMatches = await fetchAllFixturesForDate(
      apiKey,
      formatDate(now),
  );

  if (todayMatches.length > 0) {
    for (const match of todayMatches) {
      const date = match.date;
      const fixtureId = match.fixtureId.toString();
      await db.ref(`matchPool/${date}/${fixtureId}`).set(match);
      uniqueLeagues.add(match.leagueId);
    }
    totalMatches += todayMatches.length;
    functions.logger.info(`✅ Bugün: ${todayMatches.length} maç eklendi`);
  }

  // Rate limit koruması
  await sleep(500);

  // YARIN'IN TÜM MAÇLARINI ÇEK
  functions.logger.info("📥 Yarın oynanan tüm maçlar çekiliyor...");
  const tomorrowMatches = await fetchAllFixturesForDate(
      apiKey,
      formatDate(tomorrow),
  );

  if (tomorrowMatches.length > 0) {
    for (const match of tomorrowMatches) {
      const date = match.date;
      const fixtureId = match.fixtureId.toString();
      await db.ref(`matchPool/${date}/${fixtureId}`).set(match);
      uniqueLeagues.add(match.leagueId);
    }
    totalMatches += tomorrowMatches.length;
    functions.logger.info(`✅ Yarın: ${tomorrowMatches.length} maç eklendi`);
  }

  // Metadata güncelle
  const nextUpdate = now.getTime() + (6 * 60 * 60 * 1000); // 6 saat sonra
  await db.ref("poolMetadata").update({
    lastUpdate: admin.database.ServerValue.TIMESTAMP,
    totalMatches: totalMatches,
    leagues: Array.from(uniqueLeagues),
    leagueCount: uniqueLeagues.size,
    nextUpdate: nextUpdate,
  });

  // Eski maçları temizle (3 saatten eski)
  await cleanOldMatches(db);

  functions.logger.info(
      `🎉 Toplam ${totalMatches} maç güncellendi (${uniqueLeagues.size} farklı lig)`,
  );

  return {
    totalMatches,
    leagues: uniqueLeagues.size,
    timestamp: now.toISOString(),
  };
}

/**
 * Belirli bir tarihteki TÜM maçları çek (tüm ligler)
 * @param {string} apiKey - Football API key
 * @param {string} date - Date (YYYY-MM-DD)
 * @return {Promise<Array>} Matches array
 */
async function fetchAllFixturesForDate(apiKey, date) {
  const url = `https://v3.football.api-sports.io/fixtures?date=${date}`;

  try {
    functions.logger.info(`📡 API Request: /fixtures?date=${date}`);

    const data = await makeHttpsRequest(url, apiKey);
    const fixtures = data.response || [];

    functions.logger.info(`📊 API Response: ${fixtures.length} maç bulundu`);

    const matches = [];

    for (const fixture of fixtures) {
      // Rate limit koruması
      await sleep(200);

      const homeTeamId = fixture.teams.home.id;
      const awayTeamId = fixture.teams.away.id;
      const leagueId = fixture.league.id;

      // Stats çek (opsiyonel - hata olsa bile devam et)
      let homeStats = null;
      let awayStats = null;
      let h2h = [];

      try {
        homeStats = await fetchTeamStats(apiKey, homeTeamId, leagueId);
        await sleep(200);

        awayStats = await fetchTeamStats(apiKey, awayTeamId, leagueId);
        await sleep(200);

        h2h = await fetchH2H(apiKey, homeTeamId, awayTeamId);
      } catch (statsError) {
        functions.logger.warn(
            `⚠️ Stats alınamadı (Fixture ${fixture.fixture.id}):`,
            statsError.message,
        );
      }

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
    functions.logger.error(`❌ Tarih ${date} çekme hatası:`, error.message);
    return [];
  }
}

/**
 * Takım istatistikleri çek
 * @param {string} apiKey - Football API key
 * @param {number} teamId - Team ID
 * @param {number} leagueId - League ID
 * @return {Promise<Object>} Team stats
 */
async function fetchTeamStats(apiKey, teamId, leagueId) {
  const season = new Date().getFullYear();
  const url = `https://v3.football.api-sports.io/teams/statistics` +
    `?team=${teamId}&season=${season}&league=${leagueId}`;

  try {
    const data = await makeHttpsRequest(url, apiKey);
    return data.response || null;
  } catch (error) {
    functions.logger.warn(
        `⚠️ Stats alınamadı (Team ${teamId}):`,
        error.message,
    );
    return null;
  }
}

/**
 * H2H (Head to Head) çek
 * @param {string} apiKey - Football API key
 * @param {number} team1Id - Team 1 ID
 * @param {number} team2Id - Team 2 ID
 * @return {Promise<Array>} H2H matches
 */
async function fetchH2H(apiKey, team1Id, team2Id) {
  const url = `https://v3.football.api-sports.io/fixtures/headtohead?h2h=${team1Id}-${team2Id}`;

  try {
    const data = await makeHttpsRequest(url, apiKey);
    return data.response || [];
  } catch (error) {
    functions.logger.warn(`⚠️ H2H alınamadı:`, error.message);
    return [];
  }
}

/**
 * HTTPS isteği yap
 * @param {string} url - Request URL
 * @param {string} apiKey - Football API key
 * @return {Promise<Object>} API response
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
 * @param {Object} db - Firebase database reference
 * @return {Promise<void>} Cleanup result
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
      functions.logger.info(`🗑️ ${deletedCount} eski maç temizlendi`);
    }
  }
}

// Helper functions
/**
 * Format date to YYYY-MM-DD
 * @param {Date} date - Date object
 * @return {string} Formatted date
 */
function formatDate(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

/**
 * Clean Turkish characters from team name
 * @param {string} name - Team name
 * @return {string} Cleaned name
 */
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

/**
 * Sleep helper function
 * @param {number} ms - Milliseconds to sleep
 * @return {Promise<void>} Sleep promise
 */
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
