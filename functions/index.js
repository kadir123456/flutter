/**
 * Firebase Cloud Functions - AI Spor Pro
 * Otomatik Match Pool Güncelleme
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const https = require("https");
const axios = require("axios");

// Firebase Admin initialize
admin.initializeApp();

// ============================================
// 🔐 GÜVENLİK: API PROXY FUNCTIONS
// API anahtarları artık sadece Cloud Functions'da
// ============================================

/**
 * 🤖 GEMINI API PROXY (Güvenli)
 * Client'tan gelen istekleri Gemini'ye proxy yapar
 * API key sadece burada saklanır
 */
exports.callGeminiAPI = functions.https.onCall(async (data, context) => {
  // Debug: Context bilgilerini logla
  functions.logger.info("🔍 callGeminiAPI çağrıldı");
  functions.logger.info("Context auth:", context.auth ? "Var" : "YOK!");
  functions.logger.info("Gelen data keys:", Object.keys(data));

  if (context.auth) {
    functions.logger.info("User ID:", context.auth.uid);
    functions.logger.info("User token:", context.auth.token ? "Var" : "Yok");
  }

  // ⚠️ GEÇİCİ: Auth kontrolü devre dışı (test için)
  if (!context.auth) {
    functions.logger.warn(
        "⚠️ UYARI: Auth olmadan devam ediliyor (TEST MODE)",
    );
  }

  // Data içeriğini detaylı logla
  // Firebase Functions v2 için data wrapper kontrolü
  const requestData = data.data || data;
  const {prompt, imageBase64} = requestData;

  const promptInfo = prompt ?
    `Evet (${prompt.length} karakter)` : "YOK!";
  const imageInfo = imageBase64 ?
    `Evet (${imageBase64.length} karakter)` : "YOK!";

  functions.logger.info("📝 Prompt var mı?", promptInfo);
  functions.logger.info("🖼️ ImageBase64 var mı?", imageInfo);

  if (!prompt) {
    functions.logger.error("❌ HATA: Prompt boş veya undefined!");
    functions.logger.error("Data wrapper keys:", Object.keys(data));
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Prompt gereklidir",
    );
  }

  try {
    // Remote Config'den API key al (sadece server-side)
    const db = admin.database();
    const apiKeySnapshot = await db.ref("remoteConfig/GEMINI_API_KEY").get();
    const apiKey = apiKeySnapshot.val();

    if (!apiKey) {
      throw new Error("GEMINI_API_KEY yapılandırılmamış");
    }

    // context.auth null check ekle
    const userId = context.auth ? context.auth.uid : "anonymous";
    functions.logger.info(`🤖 Gemini API çağrısı - User: ${userId}`);

    // Gemini API'ye istek gönder
    const geminiUrl = "https://generativelanguage.googleapis.com" +
      `/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`;

    const requestBody = {
      contents: [{
        parts: [],
      }],
      generationConfig: {
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
        maxOutputTokens: 8192,
      },
    };

    // Text ekle
    requestBody.contents[0].parts.push({
      text: prompt,
    });

    // Görsel varsa ekle
    if (imageBase64) {
      requestBody.contents[0].parts.push({
        inlineData: {
          mimeType: "image/jpeg",
          data: imageBase64,
        },
      });
    }

    functions.logger.info("📡 Gemini API'ye istek gönderiliyor...");

    const response = await axios.post(geminiUrl, requestBody, {
      headers: {"Content-Type": "application/json"},
      timeout: 60000, // 60 saniye timeout
    });

    const result = response.data;

    if (!result.candidates || result.candidates.length === 0) {
      throw new Error("Gemini API'den yanıt alınamadı");
    }

    const text = result.candidates[0].content.parts[0].text;

    functions.logger.info("✅ Gemini API başarılı");

    return {
      success: true,
      text: text,
      usage: result.usageMetadata,
    };
  } catch (error) {
    functions.logger.error("❌ Gemini API hatası:", error.message);
    functions.logger.error("Stack trace:", error.stack);

    throw new functions.https.HttpsError(
        "internal",
        `Gemini API hatası: ${error.message}`,
    );
  }
});

/**
 * ⚽ FOOTBALL API PROXY (Güvenli)
 * Client'tan gelen istekleri Football API'ye proxy yapar
 * API key sadece burada saklanır
 */
exports.callFootballAPI = functions.https.onCall(async (data, context) => {
  // Debug: Context bilgilerini logla
  functions.logger.info("🔍 callFootballAPI çağrıldı");
  functions.logger.info("Context auth:", context.auth ? "Var" : "YOK!");
  if (context.auth) {
    functions.logger.info("User ID:", context.auth.uid);
  }

  // ⚠️ GEÇİCİ: Auth kontrolü devre dışı (test için)
  // TODO: Test sonrası tekrar aktif edilecek
  if (!context.auth) {
    functions.logger.warn("⚠️ UYARI: Auth olmadan devam ediliyor (TEST MODE)");
    // throw new functions.https.HttpsError(
    //     "unauthenticated",
    //     "Bu işlem için giriş yapmalısınız",
    // );
  }

  const {endpoint, params} = data;

  if (!endpoint) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Endpoint gereklidir",
    );
  }

  try {
    // Remote Config'den API key al
    const db = admin.database();
    const apiKeySnapshot = await db.ref("remoteConfig/API_FOOTBALL_KEY").get();
    const apiKey = apiKeySnapshot.val();

    if (!apiKey) {
      throw new Error("API_FOOTBALL_KEY yapılandırılmamış");
    }

    functions.logger.info(
        `⚽ Football API - User: ${context.auth.uid}, EP: ${endpoint}`,
    );

    // Football API'ye istek gönder
    const baseUrl = "https://v3.football.api-sports.io";
    const url = `${baseUrl}${endpoint}`;

    const response = await axios.get(url, {
      headers: {
        "x-apisports-key": apiKey,
      },
      params: params || {},
      timeout: 30000, // 30 saniye timeout
    });

    functions.logger.info("✅ Football API başarılı");

    return {
      success: true,
      data: response.data,
    };
  } catch (error) {
    functions.logger.error("❌ Football API hatası:", error.message);

    throw new functions.https.HttpsError(
        "internal",
        `Football API hatası: ${error.message}`,
    );
  }
});

// ============================================
// ⚽ MATCH POOL GÜNCELLEMESİ (Mevcut)
// ============================================

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
      `🎉 Toplam ${totalMatches} maç güncellendi ` +
      `(${uniqueLeagues.size} farklı lig)`,
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
      const homeTeamId = fixture.teams.home.id;
      const awayTeamId = fixture.teams.away.id;
      const leagueId = fixture.league.id;

      // Stats ve H2H çekme geçici olarak devre dışı
      // (Timeout sorununu önlemek için)
      // İstersen sonra aktif ederiz
      const homeStats = null;
      const awayStats = null;
      const h2h = [];

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

// Stats ve H2H fonksiyonları geçici olarak devre dışı
// (Timeout sorununu önlemek için yoruma alındı)
// İstersen sonra aktif ederiz

/*
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
*/

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
        "x-apisports-key": apiKey,
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

// ============================================
// 🔐 IN-APP PURCHASE FUNCTIONS KALDIRILDI
// Firebase Functions maliyetli ve hata verdiği için kaldırıldı
// Google Play Store satın alma işlemleri artık client-side yapılıyor
// Basit güvenlik için local cache ve duplicate kontrolü kullanılıyor
// ============================================
