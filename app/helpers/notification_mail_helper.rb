# Style tokens for the notification mail layout.
#
# One map, so the badge at the top of a message, the rule above the card and the
# callout inside it all agree on the same colour. A template names a category and
# nothing else: it never repeats a hex value, and a template that forgets to name
# one still renders, in the neutral brand colour.
#
# Where an email is about a task status, it takes that status's own colour, so a
# status looks the same in the inbox as it does in the app. Where an email is not
# about a status, the colour still has to mean something: green for finished, red
# for broken, amber for a deadline, brand blue for neutral. No shade here is
# invented.
module NotificationMailHelper
  BRAND = '#3939ff'.freeze

  # OnTrack's task status palette, copied from the web app's
  # src/styles/tokens/_light.scss. Every one of these is designed to carry white
  # text, which is what the badge draws on it.
  STATUS_COLOURS = {
    'ready-for-feedback' => '#0078d5',
    'not-started' => '#757575',
    'working-on-it' => '#a86604',
    'need-help' => '#8366bc',
    'fix-and-resubmit' => '#8b750b',
    'feedback-exceeded' => '#ca4e33',
    'redo' => '#804000',
    'discuss' => '#20809c',
    'rediscuss' => '#126352',
    'demonstrate' => '#337ab7',
    'complete' => '#3b863b',
    'fail' => '#d93713',
    'time-exceeded' => '#d93713',
    'assess-in-portfolio' => '#8b750b',
    'attention-required' => '#cd4c10'
  }.freeze

  # The glyph each status carries when a message is about that status alone.
  STATUS_GLYPHS = {
    'ready-for-feedback' => { glyph: '&#10003;', size: '24px' },
    'not-started' => { glyph: '&#9675;', size: '22px' },
    'working-on-it' => { glyph: '&#9998;', size: '22px' },
    'need-help' => { glyph: '?', size: '26px' },
    'fix-and-resubmit' => { glyph: '&#8635;', size: '24px' },
    'feedback-exceeded' => { glyph: '&#9650;', size: '20px' },
    'redo' => { glyph: '&#8635;', size: '24px' },
    'discuss' => { glyph: '&#9679;&#9679;&#9679;', size: '11px' },
    'rediscuss' => { glyph: '&#9679;&#9679;&#9679;', size: '11px' },
    'demonstrate' => { glyph: '&#9654;', size: '20px' },
    'complete' => { glyph: '&#10003;', size: '24px' },
    'fail' => { glyph: '&#10007;', size: '24px' },
    'time-exceeded' => { glyph: '&#9650;', size: '20px' },
    'assess-in-portfolio' => { glyph: '&#9636;', size: '22px' },
    'attention-required' => { glyph: '!', size: '26px' }
  }.freeze

  # Glyphs are written as HTML entities so the file stays ASCII and no mail
  # client has to guess at an encoding. Each one was rendered on a coloured disc
  # before it was chosen, which is how the clock and hourglass candidates were
  # dropped: they default to emoji presentation and arrive as a colour picture
  # sitting on a coloured circle. Everything kept is text presentation from a
  # block the core fonts cover.
  CATEGORIES = {
    'submission' => { glyph: '&#10003;', size: '24px', status: 'complete' },
    'ready_for_feedback' => { glyph: '&#10003;', size: '24px', status: 'ready-for-feedback' },
    'portfolio' => { glyph: '&#9636;', size: '22px', status: 'complete' },
    'feedback' => { glyph: '&#9998;', size: '22px', accent: BRAND },
    'comment' => { glyph: '&#9679;&#9679;&#9679;', size: '11px', accent: BRAND },
    'discuss' => { glyph: '&#9679;&#9679;&#9679;', size: '11px', status: 'discuss' },
    'help' => { glyph: '?', size: '26px', status: 'need-help' },
    'announcement' => { glyph: '&#9873;', size: '24px', accent: BRAND },
    'new' => { glyph: '&#9733;', size: '22px', accent: BRAND },
    'session' => { glyph: '&#9719;', size: '24px', accent: BRAND },
    'change' => { glyph: '&#8635;', size: '24px', accent: BRAND },
    'extension' => { glyph: '&#8677;', size: '24px', accent: BRAND },
    'group' => { glyph: '&#8258;', size: '24px', accent: BRAND },
    'verification' => { glyph: '@', size: '22px', accent: BRAND },
    'summary' => { glyph: '&#8801;', size: '24px', accent: BRAND },
    'due' => { glyph: '!', size: '26px', status: 'working-on-it' },
    'overdue' => { glyph: '&#9650;', size: '20px', status: 'time-exceeded' },
    'alert' => { glyph: '&#10007;', size: '24px', status: 'fail' }
  }.freeze

  DEFAULT_CATEGORY = { glyph: '&#9733;', size: '22px', accent: BRAND }.freeze

  # Look up a category. Two forms are accepted: a category name, and
  # "status:<key>" for a message that carries whatever status a task is actually
  # in. An unknown or blank name falls back to the neutral brand styling rather
  # than raising, because a message that renders plainly is a far better failure
  # than one that does not send at all.
  def notification_mail_style(category)
    key = category.to_s.strip
    entry =
      if key.start_with?('status:')
        status_entry(key.delete_prefix('status:'))
      else
        CATEGORIES[key]
      end
    entry ||= DEFAULT_CATEGORY

    accent = entry[:accent] || STATUS_COLOURS[entry[:status]] || BRAND
    { glyph: entry[:glyph], size: entry[:size], accent: accent, tint: notification_mail_tint(accent) }
  end

  def notification_mail_accent(category)
    notification_mail_style(category)[:accent]
  end

  # Turn a task status into the name of a style. Task#status hands back a symbol
  # such as :ready_for_feedback, while the web app's token for the same status is
  # ready-for-feedback.
  def notification_mail_status_category(status)
    key = status.to_s.tr('_', '-')
    STATUS_COLOURS.key?(key) ? "status:#{key}" : nil
  end

  # The callout behind a colour: the same hue mixed most of the way to white.
  # Derived rather than listed, so there is no second palette to drift.
  def notification_mail_tint(accent)
    notification_mail_mix(accent, 255, 0.08) || '#f5f5ff'
  end

  # The same hue, darkened, for small text sitting on that tint. The status
  # colours are built to carry white on a solid fill, which is a different job
  # from carrying themselves on a pale wash: measured on the tint, the accents
  # land near 4.1 against the 4.5 that 12px bold needs. Mixing a third of the
  # way to black clears it without a second list of hexes to keep in step.
  def notification_mail_text_accent(accent)
    notification_mail_mix(accent, 0, 0.68) || '#1f2937'
  end

  # Blend a hex colour towards `towards` (0 for black, 255 for white), keeping
  # `weight` of the original.
  def notification_mail_mix(accent, towards, weight)
    hex = accent.to_s.delete_prefix('#')
    return nil unless hex.length == 6

    mixed = hex.scan(/../).map { |pair| ((pair.to_i(16) * weight) + (towards * (1 - weight))).round.clamp(0, 255) }
    format('#%02x%02x%02x', *mixed)
  end

  private

  def status_entry(key)
    return nil unless STATUS_COLOURS.key?(key)

    STATUS_GLYPHS.fetch(key, { glyph: '&#9998;', size: '22px' }).merge(status: key)
  end
end
