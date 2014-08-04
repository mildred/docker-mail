require ["imap4flags"];

if header :contains ["Submission"] ["+submission@"] {
  addflag "\\Seen";
}
