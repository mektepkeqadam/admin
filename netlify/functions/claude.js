// Серверный прокси к Claude API.
// Ключ берётся из переменной окружения ANTHROPIC_API_KEY (настраивается в панели
// Netlify) и НИКОГДА не попадает в браузер — фронтенд обращается только сюда,
// а реальный ключ подставляется на сервере.

const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = 'claude-opus-4-8';

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: JSON.stringify({ error: 'Method Not Allowed' }) };
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return {
      statusCode: 500,
      body: JSON.stringify({ error: 'ANTHROPIC_API_KEY не задан в настройках Netlify' }),
    };
  }

  let payload;
  try {
    payload = JSON.parse(event.body || '{}');
  } catch (e) {
    return { statusCode: 400, body: JSON.stringify({ error: 'Некорректный JSON' }) };
  }

  // Берём из запроса только безопасные поля; модель задаём на сервере.
  const body = {
    model: MODEL,
    max_tokens: payload.max_tokens || 1000,
    messages: payload.messages || [],
  };
  if (payload.system) body.system = payload.system;

  try {
    const res = await fetch(ANTHROPIC_URL, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(body),
    });

    const text = await res.text();
    return {
      statusCode: res.status,
      headers: { 'content-type': 'application/json' },
      body: text,
    };
  } catch (e) {
    return { statusCode: 502, body: JSON.stringify({ error: 'Ошибка обращения к Claude API' }) };
  }
};
