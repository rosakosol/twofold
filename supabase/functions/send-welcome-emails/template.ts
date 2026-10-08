// The welcome email's HTML (docs/TWOFOLD_WEBSITE.md, section 9.3): the redesigned template,
// light and dark, with Outlook fallbacks. Kept here, beside the function that sends it, as the one
// copy; it was supabase/templates/welcome.html.
//
// Every value that came from a person (the name, the address) is escaped by the caller's
// `escapeHtml` before it reaches here.

const OPEN_URL = "https://apps.apple.com/app/id6789054723";

export function welcomeHtml({
  firstName,
  email,
  preferencesUrl,
  supportEmail,
}: {
  firstName: string;
  email: string;
  preferencesUrl: string;
  supportEmail: string;
}): string {
  // No name, no comma: "Welcome to Twofold" rather than "Welcome to Twofold, ".
  const heading = firstName ? `Welcome to Twofold, ${firstName}` : "Welcome to Twofold";
  const SUPPORT_EMAIL = supportEmail;
  return `<!DOCTYPE html>
<html lang="en" xmlns:v="urn:schemas-microsoft-com:vml">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<meta name="x-apple-disable-message-reformatting">
<title>Welcome to Twofold</title>
<!--[if mso]><style>body,table,td,a,span{font-family:Arial,Helvetica,sans-serif !important}</style><![endif]-->
<style>
  body{margin:0;padding:0}
  a{color:#1767D0}
  @media only screen and (max-width:620px){
    .sp{padding-left:24px !important;padding-right:24px !important}
    .h1{font-size:26px !important;line-height:32px !important}
    .wrap{width:100% !important}
  }
  @media (prefers-color-scheme: dark){
    .wm-ink{display:none !important}.wm-light{display:block !important;max-height:none !important;overflow:visible !important}
    .bg{background-color:#0B0F16 !important;background-image:none !important}
    .card{background-color:#141A23 !important;border-color:#1F2732 !important}
    .ink{color:#F3F5F8 !important}
    .body{color:#A6AFBC !important}
    .lnk{color:#6AA5F5 !important}
    .well{background-color:#1B222D !important;border-color:#29313D !important}
    .rule{border-color:#1F2732 !important}
    .num{background-color:#1F2C3B !important;color:#6AA5F5 !important}
  }
  [data-ogsc] .ink{color:#F3F5F8 !important}
  [data-ogsc] .wm-ink{display:none !important}
  [data-ogsc] .wm-light{display:block !important;max-height:none !important;overflow:visible !important}
  [data-ogsc] .body{color:#A6AFBC !important}
  [data-ogsc] .lnk{color:#6AA5F5 !important}
</style>
</head>
<body class="bg" style="margin:0;padding:0;background-color:#E4F0F7;background-image:linear-gradient(180deg,#DCEEF8 0%,#E3F2EA 100%);-webkit-text-size-adjust:100%;">
<span style="display:none;font-size:1px;color:#E4F0F7;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;">You&#8217;ve got your own corner of the map now.&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;</span>
<table role="presentation" class="bg" cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#E4F0F7;background-image:linear-gradient(180deg,#DCEEF8 0%,#E3F2EA 100%);">
<tr><td align="center" style="padding:32px 12px 48px 12px;">
  <table role="presentation" class="wrap" cellpadding="0" cellspacing="0" border="0" width="600" style="width:600px;max-width:600px;">
    <tr><td align="center" style="padding:8px 0 22px 0;">
      <!-- Wordmark, as the app's TwofoldBrandMark: the globe above "twofold", 32px mark, 4px gap.
           The word is an image of the app's own glyphs (New York at title2), the same outlines as
           the site's Wordmark.tsx: as text it only looked right in Apple Mail. -->
      <img src="https://www.twofoldapp.com.au/assets/globe-heart.png" width="32" height="32" alt="" style="display:block;margin:0 auto;border:0;">
      <div style="height:4px;line-height:4px;font-size:4px;mso-line-height-rule:exactly;">&nbsp;</div>
      <img class="wm-ink" src="https://www.twofoldapp.com.au/assets/wordmark-email-ink@2x.png" width="79" height="17" alt="twofold" style="display:block;margin:0 auto;border:0;">
      <!--[if !mso]><!--><div class="wm-light" style="display:none;max-height:0;overflow:hidden;mso-hide:all;"><img src="https://www.twofoldapp.com.au/assets/wordmark-email-light@2x.png" width="79" height="17" alt="twofold" style="display:block;margin:0 auto;border:0;"></div><!--<![endif]-->
    </td></tr>
    <tr><td class="card" style="background-color:#FFFFFF;border-radius:24px;border:1px solid rgba(14,26,38,.06);overflow:hidden;">
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="width:100%;">
        <tr><td height="6" style="height:6px;line-height:6px;font-size:0;background-color:#1A6FD6;background-image:linear-gradient(90deg,#3A56D9 0%,#1A6FD6 35%,#00838F 70%,#00875F 100%);border-radius:24px 24px 0 0;">&nbsp;</td></tr>
        <tr><td class="sp h1 ink" style="padding:40px 48px 0 48px;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',Arial,Helvetica,sans-serif;font-size:30px;font-weight:bold;line-height:38px;mso-line-height-rule:exactly;letter-spacing:-.01em;color:#0E1A26;">${heading}</td></tr>
        <tr><td class="sp body" style="padding:16px 48px 0 48px;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',Arial,Helvetica,sans-serif;font-size:16px;line-height:26px;mso-line-height-rule:exactly;color:#52606E;">You&#8217;ve got your own corner of the map now: a place for the flights you take to see each other, the countdowns in between, and the memories you make when you&#8217;re finally in the same city.</td></tr>
        <tr><td class="sp" style="padding:28px 48px 0 48px;">
          <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="width:100%;">
            <tr><td valign="top" style="padding:0 0 18px 0;width:44px;"><div class="num" style="width:32px;height:32px;border-radius:999px;background-color:#E6EEFB;color:#1767D0;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',Arial,Helvetica,sans-serif;font-size:15px;font-weight:bold;line-height:32px;text-align:center;">1</div></td>
              <td valign="top" style="padding:4px 0 18px 0;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',Arial,Helvetica,sans-serif;"><div class="ink" style="font-size:16px;font-weight:bold;line-height:22px;color:#0E1A26;">Connect with your partner</div><div class="body" style="padding-top:4px;font-size:15px;line-height:23px;color:#52606E;">Send your invite link from the app. Everything you add after that belongs to both of you.</div></td></tr>
            <tr><td valign="top" style="padding:0 0 18px 0;width:44px;"><div class="num" style="width:32px;height:32px;border-radius:999px;background-color:#E6EEFB;color:#1767D0;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',Arial,Helvetica,sans-serif;font-size:15px;font-weight:bold;line-height:32px;text-align:center;">2</div></td>
              <td valign="top" style="padding:4px 0 18px 0;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',Arial,Helvetica,sans-serif;"><div class="ink" style="font-size:16px;font-weight:bold;line-height:22px;color:#0E1A26;">Add your next trip or flight</div><div class="body" style="padding-top:4px;font-size:15px;line-height:23px;color:#52606E;">Twofold tracks the flight and lets your partner know the moment you land.</div></td></tr>
            <tr><td valign="top" style="padding:0 0 18px 0;width:44px;"><div class="num" style="width:32px;height:32px;border-radius:999px;background-color:#E6EEFB;color:#1767D0;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',Arial,Helvetica,sans-serif;font-size:15px;font-weight:bold;line-height:32px;text-align:center;">3</div></td>
              <td valign="top" style="padding:4px 0 18px 0;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',Arial,Helvetica,sans-serif;"><div class="ink" style="font-size:16px;font-weight:bold;line-height:22px;color:#0E1A26;">Answer today&#8217;s question together</div><div class="body" style="padding-top:4px;font-size:15px;line-height:23px;color:#52606E;">One question a day, and a streak to keep between you.</div></td></tr>
          </table>
        </td></tr>
        <tr><td class="sp" style="padding:28px 48px 0 48px;">
          <!--[if mso]><v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" href="${OPEN_URL}" style="height:50px;v-text-anchor:middle;width:200px;" arcsize="50%" stroke="f" fillcolor="#1767D0"><center style="color:#FFFFFF;font-family:Arial,sans-serif;font-size:16px;font-weight:bold;">Open Twofold</center></v:roundrect><![endif]-->
          <!--[if !mso]><!--><table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
            <td bgcolor="#1767D0" style="background-color:#1767D0;background-image:linear-gradient(135deg,#1A6FD6 0%,#1F49B8 100%);border-radius:999px;">
              <a href="${OPEN_URL}" style="display:block;padding:15px 32px;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',Arial,Helvetica,sans-serif;font-size:16px;font-weight:bold;line-height:20px;color:#FFFFFF;text-decoration:none;">Open Twofold</a>
            </td></tr></table><!--<![endif]-->
        </td></tr>
        <tr><td class="sp body" style="padding:28px 48px 0 48px;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',Arial,Helvetica,sans-serif;font-size:14px;line-height:22px;mso-line-height-rule:exactly;color:#52606E;">Questions, or something not working? Reply to this email and a real person will get back to you.</td></tr>
        <tr><td class="sp" style="padding:24px 48px 0 48px;">
          <table role="presentation" class="well" cellpadding="0" cellspacing="0" border="0" width="100%" style="width:100%;background-color:#F6F9FC;border-radius:16px;border:1px solid #E3EAF0;">
            <tr><td class="body" style="padding:16px 20px;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',Arial,Helvetica,sans-serif;font-size:14px;line-height:22px;color:#52606E;">
              <strong class="ink" style="color:#0E1A26;">Didn&#8217;t sign up for this?</strong> Someone may have mistyped their own email address and reached yours instead. Reply to this email or write to <a class="lnk" href="mailto:${SUPPORT_EMAIL}" style="color:#1767D0;">${SUPPORT_EMAIL}</a> and we&#8217;ll remove the account. Nobody can read your email or act as you: the address was only typed in, never confirmed.
            </td></tr>
          </table>
        </td></tr>
        <tr><td style="height:40px;line-height:40px;font-size:0;">&nbsp;</td></tr>
      </table>
    </td></tr>
    <tr><td align="center" class="sp body" style="padding:26px 40px 0 40px;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',Arial,Helvetica,sans-serif;font-size:13px;line-height:20px;mso-line-height-rule:exactly;color:#52606E;">
      You&#8217;re receiving this because you created a Twofold account with ${email}. <a class="lnk" href="${preferencesUrl}" style="color:#1767D0;">Email preferences</a>
    </td></tr>
    <tr><td align="center" class="body" style="padding:10px 40px 0 40px;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',Arial,Helvetica,sans-serif;font-size:13px;line-height:20px;color:#52606E;">
      Twofold, made for the couples doing long distance.<br><a class="lnk" href="https://www.twofoldapp.com.au" style="color:#1767D0;text-decoration:none;">twofoldapp.com.au</a>
    </td></tr>
  </table>
</td></tr>
</table>
</body>
</html>`;
}
