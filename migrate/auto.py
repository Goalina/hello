import json
import logging
import random

from hiascend_method import *


class ElementPost:
    """
    用于提前准备发布文章的输入
    """

    def __init__(self, topic_id, category_id, author):
        self.src_topic_id = topic_id
        self.category_id = category_id
        self.author = author

    def __dict__(self):
        return {
            "topic_id": self.src_topic_id,
            "category_id": self.category_id,
            "author": self.author,
        }


def get_category_mapping():
    """
    返回关键topic_id和对应的category_id映射
    注意：这些id必须按照在id_list中出现的顺序排列
    """
    return [
        ("0231107350879722104", 17),
        ("0232108043454406162", 19),
        ("0225131451875913067", 22),
        ("0215111067861669006", 24),
        ("0230108043108840149", 20),
    ]


def get_random_author():
    authors = ["Hanshize", "chengxiaoli", "Skyti", "huan666"]
    return random.choice(authors)


def determine_category(id_list, current_id):
    """
    根据当前id在列表中的位置确定category_id
    """
    threshold_ids = get_category_mapping()

    id_positions = {}
    for idx, tid in enumerate(id_list):
        for threshold_id, _ in threshold_ids:
            if tid == threshold_id:
                id_positions[threshold_id] = idx

    current_pos = id_list.index(current_id)

    for threshold_id, category in sorted(
        threshold_ids, key=lambda x: id_positions[x[0]]
    ):
        if current_pos < id_positions[threshold_id]:
            return category

    return 23


def create_input_list(topic_id):
    """
    用于生成自动化运行的输入文件，第一次运行该函数生成data.json文件即可
    """
    input_list = []

    # 获取完整的topic_id列表
    id_list = poster.get_list(topic_id)

    # 创建element_post列表
    for topic_id in id_list:
        category_id = determine_category(id_list, topic_id)
        # 作者信息可以根据需要修改
        author = get_random_author()
        input_list.append(ElementPost(topic_id, category_id, author))

    random.shuffle(input_list)
    x = [obj.__dict__() for obj in input_list]

    with open("data.json", "w") as f:
        json.dump(x, f, indent=4)

    # 打印结果验证
    for element in input_list:
        print(
            f"Topic ID: {element.src_topic_id}, Category ID: {element.category_id}, Author: {element.author}"
        )
    print(len(input_list), len(id_list))


if __name__ == "__main__":
    suc_count = 0
    fal_count = 0
    # 配置日志
    logging.basicConfig(level=logging.INFO)

    poster = ArticlePoster()
    with open("data.json", "r") as f:
        loaded_data = json.load(f)

    for article_data in loaded_data:
        # 获取文章内容
        content = poster.get_topic_content(article_data["topic_id"])
        if not content or not content.get("markdown"):
            logging.error(f"无法获取内容，跳过 topic_id: {article_data['topic_id']}")
            continue

        # 发布文章
        result = poster.post(
            content=content,
            category_id=article_data["category_id"],
            author=article_data["author"],
        )

        # 处理发布结果
        if result["success"]:
            logging.info(f"发布成功标题: {content.get('title', '')}")
            logging.info(f"文章链接: {result['url']}")
            with open("s.txt", "a", encoding="utf-8") as success_file:
                success_file.write(content.get("title", "") + "\n")
            suc_count += 1
            time.sleep(17280)
        else:
            fal_count += 1
            logging.error(f"发布失败！原因: {result['error']}")
            with open("e.txt", "a", encoding="utf-8") as error_file:
                error_file.write(content.get("title", "") + "\n")

        logging.info(f"成功发布{suc_count}篇, 失败{fal_count}篇")
