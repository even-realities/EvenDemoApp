# ElevenLabs 日本語向け TTS モデル & ボイスまとめ

## 1. モデルの選び方

### 🏆 おすすめモデル
- **Eleven v3**
  - 最も自然で感情豊か
  - 70+ 言語対応（日本語も含まれる可能性が高い）
  - マルチスピーカー、音声タグ対応

- **eleven_multilingual_v2**
  - 日本語を含む 29 言語対応（確実に日本語対応）
  - 安定性が高く、長文にも強い

- **eleven_flash_v2_5**
  - 超低レイテンシ（75ms）
  - 日本語を含む 32 言語対応
  - リアルタイム向け

- **eleven_turbo_v2_5**
  - 高品質 + 低レイテンシ（250–300ms）
  - 日本語を含む 32 言語対応

---

## 2. 日本語対応 Voice ID 一覧

| 名前 | voice_id | 特長 |
|------|----------|------|
| **Junichi** | `wAWUBOIVEUw9IEUYoNzR` | 中年男性・バリトン。会話に最適 |
| **Ken** | `6XNSYkDqZ1blajSVtPok` | 中年男性。ニュース読み向き |
| **Koby** | `7V2labMjY8jnJlxDRW75` | 深みのある声。ナレーション向き |
| **Ishibashi** | `Mv8AjrYZCBkdsmDHNwcB` | 東京風の強い男性声。英日両対応可 |
| **Yamato** | `bqpOyYNUu11tjjvRUbKn` | 若い男性（20–30代）。YouTube/朗読向き |
| **Kenzo** | `b34JylakFZPlGS0BnwyY` | 穏やかでプロフェッショナル。企業向け |
| **Noguchi** | `5enpi03fjGAwd9rnMfVT` | 若い男性。柔らかい声。朗読向き |
| **Hiro Satake** | `MlgbiBnm4o8N3DaDzblH` | 中年男性のナレーション |
| **Ichiro** | `LNzr3u01PIEDg0fRlvE7` | 若い男性声。物語向き |
| **Morioki** | `8EkOjt4xTPGMclNlh1pk` | 女性声。会話にも使える自然さ |
| **Ken (alt)** | `hBWDuZMNs32sP5dKzMuc` | 中年男性、ナレーション向き |

---

## 3. モデル比較表

| 順位 | モデル        | 特徴                       | 日本語対応 | 用途 |
|------|---------------|----------------------------|------------|------|
| 1⃣   | Eleven v3      | 最も自然で感情豊か          | 多言語対応（70+） | 最高品質 |
| 2⃣   | multilingual_v2 | 安定性が高くナチュラル      | ✅（29言語） | 長文・安定性重視 |
| 3⃣   | flash_v2_5      | 超低遅延 + 日本語対応       | ✅（32言語） | リアルタイム |
| 4⃣   | turbo_v2_5      | 高品質＋低遅延             | ✅（32言語） | 高速と品質のバランス |

---

## 4. 推奨構成例（日本語）

### リクエスト例（Yamato + Eleven v3）

```json
{
  "endpoint": "https://api.elevenlabs.io/v1/text-to-speech/bqpOyYNUu11tjjvRUbKn",
  "method": "POST",
  "headers": {
    "Accept": "audio/mpeg",
    "Content-Type": "application/json",
    "xi-api-key": "<YOUR_API_KEY>"
  },
  "body": {
    "text": "こんにちは、これは最高品質の日本語音声です。",
    "model_id": "eleven_v3",
    "voice_settings": {
      "stability": 0.5,
      "similarity_boost": 0.5
    },
    "output_format": "mp3_44100_128",
    "language_code": null
  }
}
```

---

## まとめ

- **最高品質**：Eleven v3 + Yamato（または好みの声）
- **安定性重視**：multilingual_v2
- **リアルタイム性重視**：flash_v2_5 / turbo_v2_5

用途に合わせて最適な組み合わせを選ぶのがおすすめです。
