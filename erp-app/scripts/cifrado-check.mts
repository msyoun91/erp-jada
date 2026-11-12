// El contrato con el portal: lo que cifra el ERP (Node) lo descifra el navegador (WebCrypto). Correr: node scripts/cifrado-check.mts
import assert from "node:assert/strict";
import { cifrar, huellaDe } from "../src/modules/presupuestos/cifrado.ts";

const link = "0123456789abcdef0123456789abcdef";
const texto = JSON.stringify({ revision: 3, nombre: "Ventanas — 2°C, ñandú", total: 21400.5 });
const enc = new TextEncoder();
const hex = (b: ArrayBuffer) => Buffer.from(b).toString("hex");

// Lo que hará el navegador
const huellaWeb = hex(await crypto.subtle.digest("SHA-256", enc.encode(`huella:${link}`)));
assert.equal(huellaDe(link), huellaWeb);
assert.match(huellaWeb, /^[0-9a-f]{64}$/);

const llave = await crypto.subtle.importKey("raw", await crypto.subtle.digest("SHA-256", enc.encode(`llave:${link}`)), "AES-GCM", false, ["decrypt"]);
const b = Buffer.from(cifrar(link, texto), "base64");
const plano = await crypto.subtle.decrypt({ name: "AES-GCM", iv: b.subarray(0, 12) }, llave, b.subarray(12));
assert.equal(new TextDecoder().decode(plano), texto);

// La huella no descifra, y dos cifrados del mismo texto difieren (iv al azar)
assert.notEqual(huellaDe(link), hex(await crypto.subtle.digest("SHA-256", enc.encode(`llave:${link}`))));
assert.notEqual(cifrar(link, texto), cifrar(link, texto));

// Otro link no descifra
const otra = await crypto.subtle.importKey("raw", await crypto.subtle.digest("SHA-256", enc.encode("llave:ffffffffffffffffffffffffffffffff")), "AES-GCM", false, ["decrypt"]);
await assert.rejects(crypto.subtle.decrypt({ name: "AES-GCM", iv: b.subarray(0, 12) }, otra, b.subarray(12)));

console.log("cifrado: 6 / 6 ok");
