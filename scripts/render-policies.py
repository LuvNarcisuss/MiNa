"""Render the in-app policies as downloadable English PDFs."""
import json
from pathlib import Path
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer
from xml.sax.saxutils import escape

root = Path(__file__).resolve().parents[1]
output = root / 'docs/policies'
output.mkdir(parents=True, exist_ok=True)
policies = json.loads((root/'ios/MiNa/policies.json').read_text())
for key in ('terms', 'privacy'):
    policy = policies[key]
    doc = SimpleDocTemplate(str(output/(key+'.pdf')), pagesize=A4, title=policy['title'],
                            author='MiNa', leftMargin=18*mm, rightMargin=18*mm,
                            topMargin=15*mm, bottomMargin=14*mm)
    title = ParagraphStyle('Title', fontName='Helvetica-Bold', fontSize=23, leading=28, textColor=colors.HexColor('#144a5b'))
    label = ParagraphStyle('Label', fontName='Helvetica-Bold', fontSize=12, leading=15, spaceBefore=10, spaceAfter=4)
    body = ParagraphStyle('Body', fontName='Helvetica', fontSize=10, leading=13.5, textColor=colors.HexColor('#243f49'))
    effective = "November 24, 2026"
    story = [Paragraph(policy['title'], title), Spacer(1, 5), Paragraph(f"Effective {effective}", body)]
    for heading, text in policy['sections']:
        story.extend([Paragraph(escape(heading), label), Paragraph(escape(text), body)])
    doc.build(story)
