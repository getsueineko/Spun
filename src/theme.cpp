#include "theme.h"
#include <QGuiApplication>
#include <QColor>
#include <QDir>
#include <QFile>
#include <QPalette>
#include <QRegularExpression>
#include <cmath>
#include <array>
#include <algorithm>

static QString read(const QString &path) {
  QFile file(path);
  return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll())
                                        : QString();
}
static QColor mix(QColor a, QColor b, qreal t) {
  return QColor::fromRgbF(a.redF() * (1 - t) + b.redF() * t,
                          a.greenF() * (1 - t) + b.greenF() * t,
                          a.blueF() * (1 - t) + b.blueF() * t);
}
static double contrast(QColor a, QColor b) {
  const auto luminance = [](QColor c) {
    const auto linear = [](double x) { return x <= .04045 ? x / 12.92 : std::pow((x + .055) / 1.055, 2.4); };
    return .2126 * linear(c.redF()) + .7152 * linear(c.greenF()) + .0722 * linear(c.blueF());
  };
  const auto first = luminance(a), second = luminance(b);
  return (std::max(first, second) + .05) / (std::min(first, second) + .05);
}
static QColor supportingText(QColor fg, QColor bg, QColor card, QColor accent) {
  const std::array surfaces{bg, card, mix(card, fg, .07), mix(card, accent, .13)};
  // Resolve this once per palette update, never per frame. Preserve the theme's
  // foreground hue while reducing muting when small text needs more contrast.
  for (int step = 32; step >= 0; --step) {
    const auto candidate = mix(fg, bg, step / 100.);
    if (std::all_of(surfaces.begin(), surfaces.end(), [&](QColor surface) { return contrast(candidate, surface) >= 4.5; }))
      return candidate;
  }
  return fg;
}
// Bake the Light and Dark palettes once: they are the same tokens Noctalia
// would have exported for the corresponding Noctalia scheme (see
// main.cpp::themeCss), so the look stays in step with the rest of the UI
// when the user pins a mode.
QVariantMap Theme::bakedLightColors() {
  return QVariantMap{
    {"surface", QColor("#f6f0e8")},
    {"text",    QColor("#342d29")},
    {"card",    QColor("#e9e0d5")},
    {"accent",  QColor("#8b492d")},
    {"onAccent",QColor("#ffffff")},
    {"muted",   QColor("#7a6f68")},
    {"outline", mix(QColor("#e9e0d5"), QColor("#342d29"), .18)},
    {"hover",   mix(QColor("#e9e0d5"), QColor("#342d29"), .07)},
    {"pressed", mix(QColor("#e9e0d5"), QColor("#342d29"), .13)},
    {"error",   QColor("#b3261e")},
  };
}
QVariantMap Theme::bakedDarkColors() {
  return QVariantMap{
    {"surface", QColor("#17191f")},
    {"text",    QColor("#eee5dc")},
    {"card",    QColor("#24252b")},
    {"accent",  QColor("#e6b599")},
    {"onAccent",QColor("#392619")},
    {"muted",   QColor("#a8a098")},
    {"outline", mix(QColor("#24252b"), QColor("#eee5dc"), .18)},
    {"hover",   mix(QColor("#24252b"), QColor("#eee5dc"), .07)},
    {"pressed", mix(QColor("#24252b"), QColor("#eee5dc"), .13)},
    {"error",   QColor("#ffb4ab")},
  };
}
Theme::Theme(const QString &configRoot, const QString &stateRoot,
             const QString &settingsPath, QObject *parent)
    : QObject(parent), m_config(configRoot), m_state(stateRoot),
      m_settings(settingsPath, QSettings::IniFormat) {
  m_debounce.setSingleShot(true);
  m_debounce.setInterval(90);
  connect(&m_watcher, &QFileSystemWatcher::fileChanged, this,
          [this] { m_debounce.start(); });
  connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this,
          [this] { m_debounce.start(); });
  connect(&m_debounce, &QTimer::timeout, this, &Theme::reload);
  // Default to System so existing installs without a stored choice behave
  // exactly as before; only an explicit value gets remembered.
  const int raw = m_settings.value("themeMode", int(System)).toInt();
  if (raw == int(Light) || raw == int(Dark))
    m_mode = Mode(raw);
  reload();
}
void Theme::watch() {
  // Watch parent directories too: generated files are often atomically
  // replaced.
  QStringList paths{m_config,
                    m_config + "/gtk-4.0",
                    m_config + "/gtk-4.0/noctalia.css",
                    m_config + "/noctalia",
                    m_config + "/noctalia/config.toml",
                    m_state,
                    m_state + "/noctalia",
                    m_state + "/noctalia/settings.toml"};
  for (const auto &path : paths)
    if (QFileInfo::exists(path) && !m_watcher.files().contains(path) &&
        !m_watcher.directories().contains(path))
      m_watcher.addPath(path);
}
void Theme::reload() {
  watch();
  const auto previous = m_colors;
  const auto oldFont = m_font;
  const qreal oldRadius = m_radius, oldMotion = m_motion;
  QMap<QString, QColor> tokens;
  const QString css = read(m_config + "/gtk-4.0/noctalia.css");
  static const QRegularExpression expression(
      "@define-color\\s+(\\w+)\\s+(#[0-9a-fA-F]{6})\\s*;");
  auto matches = expression.globalMatch(css);
  while (matches.hasNext()) {
    const auto match = matches.next();
    tokens.insert(match.captured(1), QColor(match.captured(2)));
  }
  // Keep the last complete palette while Noctalia writes/regenerates its
  // export.
  const bool complete = tokens.contains("window_bg_color") &&
                        tokens.contains("window_fg_color") &&
                        tokens.contains("accent_bg_color") &&
                        tokens.contains("accent_fg_color") &&
                        tokens.contains("card_bg_color");
  if (complete || m_baseColors.isEmpty()) {
    QColor bg = tokens.value("window_bg_color", QColor("#191919"));
    QColor fg = tokens.value("window_fg_color", QColor("#ededed"));
    QColor card = tokens.value("card_bg_color", QColor("#262626"));
    QVariantMap next{
        {"surface", bg},
        {"text", fg},
        {"card", card},
        {"accent", tokens.value("accent_bg_color", QColor("#b8c4cf"))},
        {"onAccent", tokens.value("accent_fg_color", QColor("#253440"))},
        {"muted", supportingText(fg, bg, card, tokens.value("accent_bg_color", QColor("#b8c4cf")))},
        {"outline", mix(card, fg, .18)},
        {"hover", mix(card, fg, .07)},
        {"pressed", mix(card, fg, .13)},
        {"error", tokens.value("error_bg_color", QColor("#ffb4ab"))}};
    // Only adjust System-mode resolution from the file when the export is
    // actually complete. Falling back to the hard-coded dark defaults on
    // macOS / Windows (where noctalia.css is absent) would otherwise flip
    // the OS observer's resolved state to dark and silently re-darken the
    // UI on every file watcher tick. Linux (where the file is real) is
    // unaffected.
    if (complete)
      m_systemResolvedDark = bg.lightnessF() < 0.5;
    m_baseColors = next;
  }
  m_font = "Adwaita Sans";
  m_radius = m_motion = 1;
  bool animations = true;
  static const QRegularExpression setting("^(\\w+)\\s*=\\s*(.+)$");
  for (const auto &path : QStringList{m_config + "/noctalia/config.toml",
                                      m_state + "/noctalia/settings.toml"}) {
    QString section;
    for (QString line : read(path).split('\n')) {
      line = line.trimmed();
      if (line.startsWith('[')) {
        section = line;
        continue;
      }
      // Other Noctalia sections cannot affect Spun. Compile the shared parser
      // once and only match settings in the two sections consumed below.
      if (section != "[shell]" && section != "[shell.animation]")
        continue;
      auto match = setting.match(line);
      if (!match.hasMatch())
        continue;
      const QString key = match.captured(1),
                    value = match.captured(2).split('#').first().trimmed();
      if (section == "[shell]" && key == "font_family" &&
          value.startsWith('"') && value.endsWith('"'))
        m_font = value.mid(1, value.size() - 2);
      bool ok = false;
      qreal number = value.toDouble(&ok);
      if (section == "[shell]" && key == "corner_radius_scale" && ok)
        m_radius = qBound(0., number, 2.);
      if (section == "[shell.animation]" && key == "speed" && ok)
        m_motion = qBound(.1, number, 3.);
      if (section == "[shell.animation]" && key == "enabled")
        animations = value != "false";
    }
  }
  if (!animations)
    m_motion = 0;
  // Only re-apply the palette on a real change. Forced Light/Dark modes ignore
  // the file output, so no flicker occurs when Noctalia swaps schemes: the
  // baked-in palette stays put and the watcher keeps running for when the
  // user switches back to System.
  if (m_mode == System) {
    // When the file was actually parsed (Linux with Noctalia), honour it
    // directly: m_baseColors is the source of truth. When the file was
    // missing and we fell back to the hard-coded dark defaults (macOS,
    // Windows, Linux without Noctalia), keep m_colors pointed at the baked
    // System-mode palette resolved from the OS observer — otherwise a
    // subsequent file watcher tick would silently darken the UI even when
    // the user is in Light or the OS is in Light.
    const bool usingFallback = !complete && m_baseColors.value("surface")
                                                   .value<QColor>() == QColor("#191919");
    const QVariantMap &target = usingFallback ? resolveModeColors()
                                              : m_baseColors;
    if (previous != target || oldFont != m_font || oldRadius != m_radius ||
        oldMotion != m_motion) {
      m_colors = target;
      applyPalette(m_colors, /*emitSignal=*/false);
      // Re-apply a previously-set override after the reload. Without this, a
      // macOS accent override is silently overwritten by the next TOML/CSS
      // change and the UI flashes back to the file-based accent.
      if (m_accentOverride.isValid()) applyOverrideAccent(m_accentOverride, false);
      emit changed();
    }
  } else if (previous != m_colors) {
    applyPalette(m_colors, /*emitSignal=*/false);
    if (m_accentOverride.isValid()) applyOverrideAccent(m_accentOverride, false);
  }
}
QVariantMap Theme::resolveModeColors() const {
  switch (m_mode) {
    case Light: return bakedLightColors();
    case Dark:  return bakedDarkColors();
    case System:
    default:    return m_systemResolvedDark ? bakedDarkColors()
                                             : bakedLightColors();
  }
}
void Theme::setMode(Mode mode) {
  if (mode == m_mode)
    return;
  m_mode = mode;
  m_settings.setValue("themeMode", int(m_mode));
  m_settings.sync();
  // Pick the palette the new mode should display. System mode falls back to
  // the last CSS-driven m_baseColors (re-evaluated against the current OS
  // resolution); Light/Dark pull from the baked sets.
  m_colors = resolveModeColors();
  applyPalette(m_colors, /*emitSignal=*/false);
  // Re-apply a previously-set override after the reload. Without this, a
  // macOS accent override is silently overwritten when the user switches
  // from System to Light/Dark and the UI flashes back to the file-based
  // accent baked into the light/dark palette.
  if (m_accentOverride.isValid()) applyOverrideAccent(m_accentOverride, false);
  emit changed();
  emit modeChanged();
}
void Theme::setSystemResolvedDark(bool dark) {
  if (dark == m_systemResolvedDark)
    return;
  m_systemResolvedDark = dark;
  if (m_mode != System)
    return;
  m_colors = resolveModeColors();
  applyPalette(m_colors, /*emitSignal=*/false);
  if (m_accentOverride.isValid()) applyOverrideAccent(m_accentOverride, false);
  emit changed();
}
void Theme::applyPalette(const QVariantMap &colors, bool emitSignal) {
  QPalette palette = qApp->palette();
  palette.setColor(QPalette::Window, colors["surface"].value<QColor>());
  palette.setColor(QPalette::WindowText, colors["text"].value<QColor>());
  palette.setColor(QPalette::Base, colors["surface"].value<QColor>());
  palette.setColor(QPalette::Text, colors["text"].value<QColor>());
  palette.setColor(QPalette::Button, colors["card"].value<QColor>());
  palette.setColor(QPalette::ButtonText, colors["text"].value<QColor>());
  palette.setColor(QPalette::Highlight, colors["accent"].value<QColor>());
  palette.setColor(QPalette::HighlightedText,
                   colors["onAccent"].value<QColor>());
  palette.setColor(QPalette::ToolTipBase, colors["card"].value<QColor>());
  palette.setColor(QPalette::ToolTipText, colors["text"].value<QColor>());
  qApp->setPalette(palette);
  if (emitSignal) emit changed();
}
void Theme::overrideAccent(const QColor &accent) {
  if (!accent.isValid()) return;
  m_accentOverride = accent;
  applyOverrideAccent(accent, true);
}
void Theme::applyOverrideAccent(const QColor &accent, bool emitSignal) {
  if (m_colors.isEmpty()) return; // First reload() will replay the override.
  const QColor prevAccent = m_colors.value("accent").value<QColor>();
  if (prevAccent == accent && !emitSignal) return;
  const QColor bg = m_colors.value("surface").value<QColor>();
  const QColor fg = m_colors.value("text").value<QColor>();
  const QColor card = m_colors.value("card").value<QColor>();
  m_colors["accent"] = accent;
  m_colors["muted"] = supportingText(fg, bg, card, accent);
  m_colors["onAccent"] = contrast(accent, fg) >= contrast(accent, QColor("#000000"))
                             ? QColor("#ffffff") : QColor("#000000");
  QPalette palette = qApp->palette();
  palette.setColor(QPalette::Highlight, accent);
  palette.setColor(QPalette::HighlightedText, m_colors["onAccent"].value<QColor>());
  qApp->setPalette(palette);
  if (emitSignal) emit changed();
}
