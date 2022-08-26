import sys
from bs4 import BeautifulSoup as bs


def format_html(html, none_out=False):
    with open(html, 'r') as f:
        soup = bs(f.read(), 'html.parser')

    input_str = soup.find("div", {'class':"jp-Cell-inputWrapper"}).find('pre').text.strip()
    if none_out:
        title = 'No Saved Outputs found!'
        subtitle = ''
    else:
        cell_id, timestamp = input_str.split('####')
        title = 'Saved Outputs'
        subtitle = f"cell '{cell_id}' saved @ {timestamp}\n"

    # remove input/source field
    soup.find("div", {'class':"jp-Cell-inputWrapper"}).decompose()

    title_col = '#ffffff'
    subtitle_col = '#808080'

    new_tag = soup.new_tag("h1", style=f'text-align:center;color:{title_col};background-color:#000000;')
    new_tag.string = title
    soup.insert(0, new_tag)

    new_tag = soup.new_tag("h2", style=f'text-align:center;color:{subtitle_col};')
    new_tag.string = subtitle
    soup.insert(1, new_tag)

    with open(html, "w") as file:
        file.write(str(soup))


if __name__ == '__main__':
    html_file, none_out = sys.argv[1:]
    format_html(html_file, bool(int(none_out)))
