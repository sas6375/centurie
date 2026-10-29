# Centurie — brief pour Claude Code (version test famille)

## Objectif
Construire une web app mobile (PWA) jouable par une dizaine de proches, en ligne avant le jeudi 29 octobre 2026 à 8h (heure de Paris), pour tester le jeu de prédictions Centurie sur 13 questions qui se résolvent entre le 30 octobre et le 3 novembre 2026.

## Contraintes
- Gratuit, aucun argent réel, jetons virtuels jamais vendus.
- Mobile d'abord (390 px), en français, accessible (cibles tactiles ≥ 44 px, contraste AA).
- Hébergement simple : Next.js (App Router) + Supabase (Postgres + auth magic link ou code famille) + Vercel. Une seule commande pour lancer en local.
- Pas d'app store : lien partagé par WhatsApp.

## Écrans (reprendre les maquettes « Centurie » arcade années 80)
1. **Inscription** : 3 initiales arcade (flèches haut/bas), 1 000 jetons offerts, bouton PRESS START.
2. **Accueil** : HUD (jetons, nombre de prédictions faites), liste des 13 questions avec statut (ouverte / figée / résolue), compte à rebours de clôture.
3. **Prédiction** : choix (Oui/Non ou 3-4 options), mise 50 / 100 / 250, gain potentiel recalculé en direct, bouton VALIDER. Une seule prédiction par joueur et par question ; modifiable jusqu'à la clôture.
4. **Résultat** : animation « télé brouillée → décodage → verdict », gain détaillé (base, bonus contre-courant).
5. **High scores** : classement de la famille (initiales, jetons), mis à jour en temps réel.
6. **Admin** (protégé par mot de passe) : saisir le résultat de chaque question, ou l'annuler (mises rendues).

## Règles de calcul
- Solde initial : 1 000 jetons. Mise ≤ solde disponible.
- À la clôture, p = part (%) des jetons misés sur l'option choisie, toutes mises confondues.
- Prédiction juste : gain = mise × 100 / p − mise (la mise est rendue en plus). Plafond : 10 × la mise.
- Bonus contre-courant : +20 jetons si p < 50 % et prédiction juste.
- Prédiction fausse : mise perdue.
- Question annulée : mises rendues.
- Avant la clôture, afficher la répartition provisoire (en %).

## Direction visuelle
Arcade années 80, générique (ne copier aucun logo ni typographie d'une œuvre existante).
- Couleurs : fond #0B0720 → #150A33 avec grille néon magenta en bas ; rouge #FF2E4D, cyan #3DF2FF, magenta #FF4FD8, jaune #FFD84A, texte #F4EFFF, gris #A99BD9.
- Polices Google : Press Start 2P (titres, boutons), VT323 (texte).
- Panneaux à bordure 4 px et ombre dure décalée ; barres segmentées ; scanlines légères ; icônes pixel (jeton, flamme, cœur, couronne).

## Les 13 questions (seed)
| id | question | options | clôture (Europe/Paris) | source |
|---|---|---|---|---|
| 1 | Le PSG gagne-t-il au Havre ? | Oui / Non | 2026-10-30 19:00 | LFP |
| 2 | Combien de buts au total dans Le Havre – PSG ? | 0-1 / 2-3 / 4 et + | 2026-10-30 19:00 | LFP |
| 3 | Marseille – Toulouse : quel résultat ? | OM / Nul / Toulouse | 2026-11-01 20:45 | LFP |
| 4 | Lyon marque-t-il 2 buts ou plus contre Angers ? | Oui / Non | 2026-11-01 17:15 | LFP |
| 5 | Kimi Antonelli gagne-t-il le GP du Mexique ? | Oui / Non | 2026-11-01 21:00 | F1 |
| 6 | Isack Hadjar finit-il dans le top 10 au Mexique ? | Oui / Non | 2026-11-01 21:00 | F1 |
| 7 | Pleuvra-t-il à Paris samedi 31 octobre (≥ 1 mm à Montsouris) ? | Oui / Non | 2026-10-30 22:00 | Météo-France / Infoclimat |
| 8 | Température maximale à Paris dimanche 1er novembre ? | < 12 °C / 12-15 °C / > 15 °C | 2026-10-31 22:00 | Météo-France / Infoclimat |
| 9 | Le CAC 40 clôture-t-il vendredi 30/10 plus haut que mercredi 28/10 ? | Oui / Non | 2026-10-29 22:00 | Euronext |
| 10 | Le Bitcoin vaut-il plus dimanche 1/11 à 20h que jeudi 29/10 à 20h ? | Oui / Non | 2026-10-30 20:00 | CoinMarketCap |
| 11 | Premier sondage de 1er tour publié du 29/10 au 2/11 : qui arrive 2e derrière le RN ? | Mélenchon / Philippe / Glucksmann / Autre | 2026-10-29 08:00 | Sondeur ; annulée si aucun sondage |
| 12 | La 1re partie du budget 2027 est-elle adoptée au vote solennel du mardi 3 novembre ? | Oui / Non | 2026-11-02 22:00 | Assemblée nationale (« Non » si rejet, report ou 49.3) |
| 13 | EuroMillions du vendredi 30/10 : la somme des 5 numéros dépasse-t-elle 127 ? | Oui / Non | 2026-10-30 20:00 | FDJ |

## Ordre de travail suggéré
1. Schéma Supabase (players, questions, options, predictions, results) + seed des 13 questions.
2. Logique de calcul en fonctions testées (tests unitaires sur les exemples : mise 100, p = 46 % → +117 ; bonus +20).
3. Écrans 1 → 6, puis temps réel sur les high scores.
4. Déploiement Vercel, lien à partager, vérification sur téléphone.

## État actuel (28/10/2026)
- `index.html` : page autonome servie par GitHub Pages (branche `main`, racine). Supabase via supabase-js 2.45.4 (UMD jsDelivr), connexion anonyme (un compte par appareil), polices Google Fonts.
- `supabase.sql` : tables `questions` (clôtures), `players` (3 initiales uniques), `predictions`, `results`, `admins` ; RLS : chacun voit ses pronos, ceux des autres seulement après `closes_at` ; écriture des pronos interdite après la clôture ; budget 1 000 jetons vérifié par trigger ; résultats modifiables par les seuls `admins`.
- Les 16 questions (texte, options) sont dans le tableau `Q` du script ; leurs clôtures doivent rester identiques à la table `questions`.
- Configuration : `SUPABASE_URL` et `SUPABASE_ANON_KEY` en haut du script (la clé anon est publique par conception, la sécurité repose sur les règles RLS).
- Questions maison : colonnes `text/options/theme/source` dans `questions` ; les lignes ayant un `text` s'ajoutent au tableau `Q` au chargement (ex. Q17). Les admins peuvent en créer depuis SCORES.
- Révélation : à l'ouverture, les résultats non vus (localStorage `centurie-seen-<uid>`) déclenchent l'écran télé brouillée → verdicts → bilan ; flèches ▲▼ du classement depuis la dernière révélation (`centurie-ranks-<uid>`).
- Scores calculés côté client (pari mutuel sur les questions figées). Suite possible : vue SQL pour les scores, temps réel, ajout de questions depuis un écran admin.
